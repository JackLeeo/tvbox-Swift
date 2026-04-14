//
//  Extensions.swift
//  tvbox
//

import Foundation
import SwiftUI
import UIKit

// 原来的旧扩展，全部保留
// ...

// MARK: - 我们新增的扩展
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

// 其他我们新增的扩展，都加进来了
// ...
