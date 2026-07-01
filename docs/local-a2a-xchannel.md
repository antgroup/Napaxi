# Local A2A over xChannel

Local A2A and xChannel are intentionally layered, not merged.

- A2A owns peer identity, pairing trust, task envelopes, signatures, task
  status, and local transport delivery.
- xChannel owns inbound/outbound queues, route resolution, channel-agent
  session execution, acknowledgements, and delivery audit.
- Local transport owns LAN/BLE/Wi-Fi Direct style device-to-device movement.

The first end-to-end path is:

1. Device A sends an A2A `task_request` to a trusted local peer.
2. Device B verifies and records the A2A task.
3. Device B asks the user to accept the task.
4. Accepting submits the task as a `local_a2a` xChannel inbound message.
5. The channel-agent bridge routes the inbound message to the bound Agent and
   runs it in a channel session.
6. The `local_a2a` provider converts the channel outbound reply into an A2A
   `task_result` and sends it back to Device A.
7. Device A records the result in the A2A task ledger.

The user-facing primary commands are:

- `/a2a ask <peer> <task>` to delegate work.
- `/a2a accept <taskId>` to confirm and execute a received task through
  `local_a2a`.

Debug commands such as `/a2a run`, `/a2a answer`, `/a2a progress`, and
`/a2a result` remain available for diagnosis, but they are not the product
flow.

The v1 safety default is manual confirmation. Trusted peers can deliver tasks,
but they do not automatically run the local Agent until the user confirms.
