//
//  Extensions.swift
//  tvbox
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Color Extension
extension Color {
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let tertiaryBackground = Color(.tertiarySystemBackground)
    
    static let label = Color(.label)
    static let secondaryLabel = Color(.secondaryLabel)
    static let tertiaryLabel = Color(.tertiaryLabel)
    static let quaternaryLabel = Color(.quaternaryLabel)
    
    static let tint = Color.accentColor
}

// MARK: - View Extension
extension View {
    /// Placeholder for TextEditor
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .topLeading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
    
    /// Show toast
    func toast(isPresented: Binding<Bool>, message: String, duration: TimeInterval = 2) -> some View {
        self.modifier(ToastModifier(isPresented: isPresented, message: message, duration: duration))
    }
}

// MARK: - Toast Modifier
struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let duration: TimeInterval
    
    @State private var offset: CGFloat = 100
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                VStack {
                    Spacer()
                    Text(message)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .offset(y: offset)
                        .opacity(opacity)
                        .onAppear {
                            withAnimation(.easeOut(duration: 0.3)) {
                                offset = 0
                                opacity = 1
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation(.easeIn(duration: 0.3)) {
                                    offset = 100
                                    opacity = 0
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isPresented = false
                                }
                            }
                        }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - String Extension
extension String {
    func trimmingWhitespace() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func isNotEmpty() -> Bool {
        return !isEmpty
    }
}

// MARK: - Data Extension
extension Data {
    func prettyPrintedJSONString() -> String? {
        if let json = try? JSONSerialization.jsonObject(with: self, options: []),
           let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let prettyString = String(data: data, encoding: .utf8) {
            return prettyString
        }
        return nil
    }
}

// MARK: - URL Extension
extension URL {
    func appendingQueryParameters(_ parameters: [String: String]) -> URL? {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
        components?.queryItems = parameters.map { key, value in
            URLQueryItem(name: key, value: value)
        }
        return components?.url
    }
}

// MARK: - Array Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Dictionary Extension
extension Dictionary {
    func jsonData() -> Data? {
        return try? JSONSerialization.data(withJSONObject: self, options: [])
    }
    
    func jsonString() -> String? {
        return jsonData()?.prettyPrintedJSONString()
    }
}

// MARK: - UIScreen Extension
extension UIScreen {
    static let screenWidth = UIScreen.main.bounds.width
    static let screenHeight = UIScreen.main.bounds.height
    static let screenSize = UIScreen.main.bounds.size
}

// MARK: - Image Extension
extension Image {
    func resizableToFit() -> some View {
        self.resizable()
            .scaledToFit()
    }
    
    func resizableToFill() -> some View {
        self.resizable()
            .scaledToFill()
    }
}

// MARK: - Font Extension
extension Font {
    static func caption2() -> Font {
        .caption2
    }
}

// MARK: - ScrollView Extension
extension ScrollView {
    func hideScrollIndicator() -> some View {
        self.showsVerticalScrollIndicator(false)
            .showsHorizontalScrollIndicator(false)
    }
}

// MARK: - NavigationView Extension
extension NavigationView {
    func navigationBarTitleDisplayModeLarge() -> some View {
        self.navigationBarTitleDisplayMode(.large)
    }
    
    func navigationBarTitleDisplayModeInline() -> some View {
        self.navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Task Extension
extension Task where Success == Void, Failure == Never {
    static func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Optional Extension
extension Optional {
    func `do`(_ action: (Wrapped) -> Void) {
        if let wrapped = self {
            action(wrapped)
        }
    }
    
    func mapOrDefault<T>(_ transform: (Wrapped) -> T, defaultValue: T) -> T {
        if let wrapped = self {
            return transform(wrapped)
        }
        return defaultValue
    }
}

// MARK: - Date Extension
extension Date {
    func format(_ format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    
    var timeAgo: String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.second, .minute, .hour, .day, .weekOfMonth, .month, .year], from: self, to: now)
        
        if let year = components.year, year > 0 {
            return "\(year)年前"
        } else if let month = components.month, month > 0 {
            return "\(month)月前"
        } else if let week = components.weekOfMonth, week > 0 {
            return "\(week)周前"
        } else if let day = components.day, day > 0 {
            return "\(day)天前"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)小时前"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)分钟前"
        } else {
            return "刚刚"
        }
    }
}

// MARK: - Int Extension
extension Int {
    var kFormatted: String {
        if self >= 10000 {
            return String(format: "%.1f万", Double(self) / 10000)
        } else if self >= 1000 {
            return String(format: "%.1fk", Double(self) / 1000)
        } else {
            return "\(self)"
        }
    }
}

// MARK: - Double Extension
extension Double {
    var roundedToPlaces: String {
        String(format: "%.2f", self)
    }
}

// MARK: - Bool Extension
extension Bool {
    var intValue: Int {
        return self ? 1 : 0
    }
}
