import Foundation
import OpenTelemetryProtocolExporterCommon

struct TelemetryLogRecord {
    let timestamp: Date
    let body: String?
    let attributes: [String: TelemetryAttributeValue]
}

struct TelemetryMetricPoint {
    let name: String
    let value: Double
    let attributes: [String: TelemetryAttributeValue]
}

enum TelemetryAttributeValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .null:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        case .bool(let value):
            return value ? 1 : 0
        case .null:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            return (value as NSString).boolValue
        case .int(let value):
            return value != 0
        case .double(let value):
            return value != 0
        case .null:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .string(let value):
            return Double(value)
        case .bool, .null:
            return nil
        }
    }
}

final class OTLPDecoder {
    func decodeLogs(_ data: Data) throws -> [TelemetryLogRecord] {
        let request = try Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest(serializedData: data)
        var records: [TelemetryLogRecord] = []

        for resourceLog in request.resourceLogs {
            for scopeLog in resourceLog.scopeLogs {
                for record in scopeLog.logRecords {
                    let timestamp = Self.timestamp(from: record.timeUnixNano, fallback: record.observedTimeUnixNano)
                    let attributes = Self.decodeAttributes(record.attributes)
                    let body = Self.stringValue(from: record.body)
                    records.append(.init(timestamp: timestamp, body: body, attributes: attributes))
                }
            }
        }

        return records
    }

    func decodeMetrics(_ data: Data) throws -> [TelemetryMetricPoint] {
        let request = try Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest(serializedData: data)
        var points: [TelemetryMetricPoint] = []

        for resourceMetric in request.resourceMetrics {
            for scopeMetric in resourceMetric.scopeMetrics {
                for metric in scopeMetric.metrics {
                    switch metric.data {
                    case .gauge(let gauge):
                        points.append(contentsOf: Self.metricPoints(from: metric.name, dataPoints: gauge.dataPoints))
                    case .sum(let sum):
                        points.append(contentsOf: Self.metricPoints(from: metric.name, dataPoints: sum.dataPoints))
                    default:
                        continue
                    }
                }
            }
        }

        return points
    }

    private static func metricPoints(
        from name: String,
        dataPoints: [Opentelemetry_Proto_Metrics_V1_NumberDataPoint]
    ) -> [TelemetryMetricPoint] {
        dataPoints.compactMap { point in
            guard let value = metricValue(from: point) else { return nil }
            let attributes = decodeAttributes(point.attributes)
            return TelemetryMetricPoint(name: name, value: value, attributes: attributes)
        }
    }

    private static func metricValue(from point: Opentelemetry_Proto_Metrics_V1_NumberDataPoint) -> Double? {
        switch point.value {
        case .asInt(let value):
            return Double(value)
        case .asDouble(let value):
            return value
        default:
            return nil
        }
    }

    private static func timestamp(from nanos: UInt64, fallback: UInt64) -> Date {
        let value = nanos != 0 ? nanos : fallback
        return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000_000.0)
    }

    private static func decodeAttributes(_ attributes: [Opentelemetry_Proto_Common_V1_KeyValue]) -> [String: TelemetryAttributeValue] {
        var decoded: [String: TelemetryAttributeValue] = [:]
        for attribute in attributes {
            decoded[attribute.key] = decodeAnyValue(attribute.value)
        }
        return decoded
    }

    private static func decodeAnyValue(_ value: Opentelemetry_Proto_Common_V1_AnyValue) -> TelemetryAttributeValue {
        switch value.value {
        case .stringValue(let string):
            return .string(string)
        case .boolValue(let bool):
            return .bool(bool)
        case .intValue(let int):
            return .int(Int(int))
        case .doubleValue(let double):
            return .double(double)
        default:
            return .null
        }
    }

    private static func stringValue(from value: Opentelemetry_Proto_Common_V1_AnyValue) -> String? {
        switch value.value {
        case .stringValue(let string):
            return string
        case .boolValue(let bool):
            return String(bool)
        case .intValue(let int):
            return String(int)
        case .doubleValue(let double):
            return String(double)
        default:
            return nil
        }
    }
}
