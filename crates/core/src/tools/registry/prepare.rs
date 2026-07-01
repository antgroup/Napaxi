//! Schema-driven argument preparation and validation.

use serde_json::Value;

use super::types::ToolDescriptor;

pub fn prepare_tool_arguments(descriptor: &ToolDescriptor, params: Value) -> Result<Value, String> {
    let schema = normalize_parameters_schema(&descriptor.parameters)?;
    let params = normalize_tool_argument_aliases(descriptor, params);
    let prepared = coerce_value_for_schema(params, &schema);
    validate_value_for_schema(&prepared, &schema, "$")?;
    Ok(prepared)
}

fn normalize_tool_argument_aliases(descriptor: &ToolDescriptor, params: Value) -> Value {
    if descriptor.name != "shell" {
        return params;
    }
    let Value::Object(mut object) = params else {
        return params;
    };
    if !object.contains_key("command")
        && let Some(cmd) = object.remove("cmd")
    {
        object.insert("command".to_string(), cmd);
    }
    Value::Object(object)
}

pub fn normalize_parameters_schema(schema: &Value) -> Result<Value, String> {
    let Some(obj) = schema.as_object() else {
        return Err("Tool parameters schema must be a JSON object".to_string());
    };
    if !schema_allows_type(schema, "object") && obj.contains_key("type") {
        return Err("Tool parameters schema must describe an object".to_string());
    }
    let mut normalized = obj.clone();
    normalized
        .entry("type".to_string())
        .or_insert_with(|| Value::String("object".to_string()));
    normalized
        .entry("properties".to_string())
        .or_insert_with(|| serde_json::json!({}));
    Ok(Value::Object(normalized))
}

pub(super) fn validate_tool_definition(def: &ToolDescriptor) -> Result<(), String> {
    if def.name.trim().is_empty() {
        return Err("Tool definition missing 'name'".to_string());
    }
    if !is_valid_tool_name(&def.name) {
        return Err(format!(
            "Tool '{}' has invalid name; use letters, numbers, '_', '-', or '.'",
            def.name
        ));
    }
    if def.description.trim().is_empty() {
        return Err(format!("Tool '{}' missing 'description'", def.name));
    }
    normalize_parameters_schema(&def.parameters)
        .map_err(|e| format!("Tool '{}' invalid parameters schema: {e}", def.name))?;
    Ok(())
}

fn is_valid_tool_name(name: &str) -> bool {
    name.chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
}

fn coerce_value_for_schema(value: Value, schema: &Value) -> Value {
    if value.is_null() {
        return value;
    }
    if let Some(s) = value.as_str() {
        if schema_allows_type(schema, "boolean") {
            match s.trim().to_ascii_lowercase().as_str() {
                "true" => return Value::Bool(true),
                "false" => return Value::Bool(false),
                _ => {}
            }
        }
        if schema_allows_type(schema, "integer")
            && let Ok(n) = s.trim().parse::<i64>()
        {
            return Value::Number(n.into());
        }
        if schema_allows_type(schema, "number")
            && let Ok(n) = s.trim().parse::<f64>()
            && let Some(number) = serde_json::Number::from_f64(n)
        {
            return Value::Number(number);
        }
        if (schema_allows_type(schema, "object") || schema_allows_type(schema, "array"))
            && let Ok(parsed) = serde_json::from_str::<Value>(s)
        {
            return coerce_value_for_schema(parsed, schema);
        }
        return value;
    }
    if let Some(arr) = value.as_array() {
        if let Some(item_schema) = schema.get("items") {
            return Value::Array(
                arr.iter()
                    .cloned()
                    .map(|item| coerce_value_for_schema(item, item_schema))
                    .collect(),
            );
        }
        return value;
    }
    if let Some(obj) = value.as_object() {
        let required = required_set(schema);
        let properties = schema.get("properties").and_then(Value::as_object);
        let additional_schema = schema.get("additionalProperties").filter(|v| v.is_object());
        let mut next = obj.clone();
        for (key, current) in &mut next {
            if let Some(prop_schema) = properties.and_then(|props| props.get(key)) {
                if current.as_str() == Some("")
                    && !required.contains(key.as_str())
                    && (schema_allows_type(prop_schema, "null")
                        || !schema_allows_type(prop_schema, "string"))
                {
                    *current = Value::Null;
                } else {
                    *current = coerce_value_for_schema(current.clone(), prop_schema);
                }
            } else if let Some(additional_schema) = additional_schema {
                *current = coerce_value_for_schema(current.clone(), additional_schema);
            }
        }
        return Value::Object(next);
    }
    value
}

fn validate_value_for_schema(value: &Value, schema: &Value, path: &str) -> Result<(), String> {
    if !matches_schema_type(value, schema) {
        return Err(format!(
            "{path} expected {}, got {}",
            expected_types(schema).join("|"),
            value_type(value)
        ));
    }

    if let Some(enum_values) = schema.get("enum").and_then(Value::as_array)
        && !enum_values.iter().any(|allowed| allowed == value)
    {
        return Err(format!(
            "{path} must be one of {}",
            Value::Array(enum_values.clone())
        ));
    }

    if let Some(obj) = value.as_object() {
        let properties = schema.get("properties").and_then(Value::as_object);
        for required in required_set(schema) {
            if !obj.contains_key(required.as_str()) {
                return Err(format!("{path}.{required} is required"));
            }
        }
        for (key, child) in obj {
            let child_path = format!("{path}.{key}");
            if let Some(child_schema) = properties.and_then(|props| props.get(key)) {
                validate_value_for_schema(child, child_schema, &child_path)?;
            } else {
                match schema.get("additionalProperties") {
                    Some(Value::Bool(false)) => {
                        return Err(format!("{child_path} is not allowed"));
                    }
                    Some(additional_schema) if additional_schema.is_object() => {
                        validate_value_for_schema(child, additional_schema, &child_path)?;
                    }
                    _ => {}
                }
            }
        }
    }

    if let Some(arr) = value.as_array()
        && let Some(item_schema) = schema.get("items")
    {
        for (idx, child) in arr.iter().enumerate() {
            validate_value_for_schema(child, item_schema, &format!("{path}[{idx}]"))?;
        }
    }

    Ok(())
}

fn matches_schema_type(value: &Value, schema: &Value) -> bool {
    let types = expected_types(schema);
    if types.is_empty() {
        return true;
    }
    types.iter().any(|schema_type| match schema_type.as_str() {
        "array" => value.is_array(),
        "boolean" => value.is_boolean(),
        "integer" => value.as_i64().is_some() || value.as_u64().is_some(),
        "number" => value.is_number(),
        "null" => value.is_null(),
        "object" => value.is_object(),
        "string" => value.is_string(),
        _ => true,
    })
}

fn schema_allows_type(schema: &Value, ty: &str) -> bool {
    expected_types(schema).iter().any(|t| t == ty)
}

fn expected_types(schema: &Value) -> Vec<String> {
    match schema.get("type") {
        Some(Value::String(ty)) => vec![ty.clone()],
        Some(Value::Array(types)) => types
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
        _ => Vec::new(),
    }
}

fn required_set(schema: &Value) -> std::collections::HashSet<String> {
    schema
        .get("required")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn value_type(value: &Value) -> &'static str {
    match value {
        Value::Array(_) => "array",
        Value::Bool(_) => "boolean",
        Value::Null => "null",
        Value::Number(number) if number.is_i64() || number.is_u64() => "integer",
        Value::Number(_) => "number",
        Value::Object(_) => "object",
        Value::String(_) => "string",
    }
}
