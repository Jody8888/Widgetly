import Foundation

enum ScheduleStore {
    static let appGroupIdentifier = "group.com.jody.widgetly"
    static let fileName = "ScheduleData.json"

    static func loadDocumentConfiguration() throws -> ScheduleConfiguration {
        let url = try prepareDocumentsFile()
        let configuration = try JSONDecoder().decode(ScheduleConfiguration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    static func loadDocumentJSON() throws -> String {
        let url = try prepareDocumentsFile()
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func saveDocumentConfiguration(_ configuration: ScheduleConfiguration) throws {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)
        try saveDocumentJSON(String(decoding: data, as: UTF8.self))
    }

    static func saveDocumentJSON(_ json: String) throws {
        let data = Data(json.utf8)
        let configuration = try JSONDecoder().decode(ScheduleConfiguration.self, from: data)
        try configuration.validate()

        let documentURL = try documentsFileURL()
        try data.write(to: documentURL, options: .atomic)
        try writeSharedCopy(data)
    }

    static func synchronizeDocumentsToWidget() throws {
        let documentURL = try prepareDocumentsFile()
        let data = try Data(contentsOf: documentURL)
        let configuration = try JSONDecoder().decode(ScheduleConfiguration.self, from: data)
        try configuration.validate()
        try writeSharedCopy(data)
    }

    static func loadWidgetConfiguration() throws -> ScheduleConfiguration {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ScheduleStoreError.sharedContainerUnavailable
        }
        let url = groupURL.appendingPathComponent(fileName)
        return try JSONDecoder().decode(ScheduleConfiguration.self, from: Data(contentsOf: url))
    }

    private static func prepareDocumentsFile() throws -> URL {
        let url = try documentsFileURL()
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        guard let bundledURL = Bundle.main.url(forResource: "ScheduleData", withExtension: "json") else {
            throw ScheduleStoreError.defaultConfigurationUnavailable
        }
        try FileManager.default.copyItem(at: bundledURL, to: url)
        return url
    }

    private static func documentsFileURL() throws -> URL {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ScheduleStoreError.documentsDirectoryUnavailable
        }
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        return documentsURL.appendingPathComponent(fileName)
    }

    private static func writeSharedCopy(_ data: Data) throws {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ScheduleStoreError.sharedContainerUnavailable
        }
        try FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true)
        try data.write(to: groupURL.appendingPathComponent(fileName), options: .atomic)
    }
}

private enum ScheduleStoreError: Error {
    case documentsDirectoryUnavailable
    case defaultConfigurationUnavailable
    case sharedContainerUnavailable
}
