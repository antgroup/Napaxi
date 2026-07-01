use serde_json::Value;

use crate::tool_registry::ToolDescriptor;

pub(super) fn openai_tool_schema(tool: &ToolDescriptor) -> Value {
    serde_json::json!({
        "type": "function",
        "function": {
            "name": tool.name,
            "description": tool.description,
            "parameters": sanitize_schema(&tool.parameters),
        }
    })
}

pub(super) fn anthropic_tool_schema(tool: &ToolDescriptor) -> Value {
    serde_json::json!({
        "name": tool.name,
        "description": tool.description,
        "input_schema": sanitize_schema(&tool.parameters),
    })
}

pub(super) fn gemini_tool_schema(tool: &ToolDescriptor) -> Value {
    serde_json::json!({
        "name": tool.name,
        "description": tool.description,
        "parameters": sanitize_schema(&tool.parameters),
    })
}

/// Normalize a JSON Schema so strict providers accept it.
///
/// Nullable MCP/Pydantic fields collapse to `{"$ref": "...", "default": null}`.
/// Some providers (e.g. Fireworks-hosted Kimi) reject any `$ref` object that
/// carries sibling keys, so the request fails before the model ever runs. Per
/// JSON Schema, sibling keys alongside `$ref` are ignored anyway, so dropping
/// them is lossless for conforming validators while keeping strict providers
/// happy. Applied recursively across the whole schema tree.
fn sanitize_schema(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let has_ref = map.contains_key("$ref");
            let mut out = serde_json::Map::with_capacity(map.len());
            for (key, child) in map {
                if has_ref && key != "$ref" {
                    continue;
                }
                if key == "type" {
                    if let Some(collapsed) = collapse_union_type(child) {
                        out.insert(key.clone(), collapsed);
                        continue;
                    }
                }
                out.insert(key.clone(), sanitize_schema(child));
            }
            Value::Object(out)
        }
        Value::Array(items) => Value::Array(items.iter().map(sanitize_schema).collect()),
        other => other.clone(),
    }
}

/// Collapse a JSON Schema union `type` array to a single concrete type.
///
/// Pydantic and MCP servers commonly emit `"type": ["string", "null"]` for
/// optional fields, but strict providers (e.g. Moonshot/Kimi) reject a `type`
/// whose value is an array. Pick the first non-`null` concrete type, falling
/// back to `"string"` when none is present. Returns `None` for non-array
/// `type` values so they pass through unchanged.
fn collapse_union_type(value: &Value) -> Option<Value> {
    let variants = value.as_array()?;
    let concrete = variants
        .iter()
        .filter_map(Value::as_str)
        .find(|t| !t.is_empty() && *t != "null")
        .unwrap_or("string");
    Some(Value::String(concrete.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn descriptor(parameters: Value) -> ToolDescriptor {
        ToolDescriptor {
            name: "demo".to_string(),
            description: "demo tool".to_string(),
            parameters,
            effect: crate::tool_registry::ToolEffect::External,
        }
    }

    #[test]
    fn strips_default_sibling_from_ref_node() {
        let schema = serde_json::json!({
            "type": "object",
            "properties": {
                "mode": { "$ref": "#/$defs/Mode", "default": null }
            }
        });
        let sanitized = openai_tool_schema(&descriptor(schema));
        let mode = &sanitized["function"]["parameters"]["properties"]["mode"];
        assert_eq!(mode, &serde_json::json!({ "$ref": "#/$defs/Mode" }));
    }

    #[test]
    fn preserves_schemas_without_ref() {
        let schema = serde_json::json!({
            "type": "object",
            "properties": {
                "count": { "type": "integer", "default": 3 }
            },
            "required": ["count"]
        });
        let sanitized = anthropic_tool_schema(&descriptor(schema.clone()));
        assert_eq!(sanitized["input_schema"], schema);
    }

    #[test]
    fn collapses_union_type_array_to_concrete_type() {
        let schema = serde_json::json!({
            "type": "object",
            "properties": {
                "name": { "type": ["string", "null"] }
            }
        });
        let sanitized = openai_tool_schema(&descriptor(schema));
        let name = &sanitized["function"]["parameters"]["properties"]["name"];
        assert_eq!(name["type"], serde_json::json!("string"));
    }

    #[test]
    fn collapses_null_first_union_type() {
        let schema = serde_json::json!({
            "type": ["null", "integer"]
        });
        let sanitized = anthropic_tool_schema(&descriptor(schema));
        assert_eq!(
            sanitized["input_schema"]["type"],
            serde_json::json!("integer")
        );
    }

    #[test]
    fn collapses_all_null_union_to_string() {
        let schema = serde_json::json!({ "type": ["null"] });
        let sanitized = gemini_tool_schema(&descriptor(schema));
        assert_eq!(sanitized["parameters"]["type"], serde_json::json!("string"));
    }

    #[test]
    fn strips_nested_ref_siblings_in_arrays() {
        let schema = serde_json::json!({
            "anyOf": [
                { "$ref": "#/$defs/A", "default": null, "title": "A" },
                { "type": "null" }
            ]
        });
        let sanitized = gemini_tool_schema(&descriptor(schema));
        let any_of = &sanitized["parameters"]["anyOf"];
        assert_eq!(any_of[0], serde_json::json!({ "$ref": "#/$defs/A" }));
        assert_eq!(any_of[1], serde_json::json!({ "type": "null" }));
    }
}
