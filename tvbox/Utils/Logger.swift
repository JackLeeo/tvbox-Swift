import Foundation
import Combine

/// 全局日志管理器，负责收集和广播日志消息
class Logger: ObservableObject {
    static let shared = Logger()
    
    @Published var messages: [LogEntry] = []
    private let maxEntries = 100
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.messages.append(entry)
            if self.messages.count > self.maxEntries {
                self.messages.removeFirst(self.messages.count - self.maxEntries)
            }
        }
        // 同时输出到控制台，便于 Xcode 调试
        print("[\(level.emoji)] \(message)")
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.messages.removeAll()
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

enum LogLevel {
    case debug, info, warning, error
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
    
    var color: String {
        switch self {
        case .debug: return "gray"
        case .info: return "white"
        case .warning: return "yellow"
        case .error: return "red"
        }
    }
}
