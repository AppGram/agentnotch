# Privacy Policy

Effective date: [YYYY-MM-DD]

AgentNotch is a macOS app that displays local AI coding assistant telemetry in the notch or menu bar. This policy explains what data the app processes and how it is handled.

## Summary

- AgentNotch processes telemetry locally to render UI status and activity.
- AgentNotch does not upload telemetry or usage data to our servers.
- App preferences are stored locally on your device.

## Data We Process

AgentNotch can receive OpenTelemetry (OTLP) events from AI coding assistants running on your machine. This data may include:

- Status and activity events (e.g., “thinking,” “tool started,” “tool completed”).
- Tool names and timing information.
- Token counts, model identifiers, status codes, and cost metadata when provided.
- Prompt length metrics (not prompt content).

AgentNotch does not intentionally collect or store full prompt content. It processes telemetry in memory to update the UI.

## How We Use Data

We use telemetry data only to:

- Update the notch/menu bar UI with live status.
- Show recent tool activity and token usage.
- Indicate errors or connectivity issues.

## Data Storage and Retention

- Telemetry is processed in memory and is not persisted to disk by AgentNotch.
- App settings (such as ports and UI preferences) are stored locally on your device.

## Data Sharing

- AgentNotch does not sell or share telemetry data.
- AgentNotch does not transmit telemetry data to our servers.
- If you use third-party AI tools, those tools may have their own policies for what they emit; AgentNotch only receives what they send locally.

## Security

AgentNotch listens for telemetry on a local port you configure. Ensure your system is configured so only trusted local processes can send telemetry to that port.

## Your Choices

You can start or stop the telemetry listener at any time in the app settings. You can also adjust which data is displayed via the settings UI.

## Changes

We may update this policy. If we make material changes, we will update the effective date.

## Contact

If you have questions, contact: [support@example.com]
