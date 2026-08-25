import SwiftUI
import UIKit

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug
    case request
    case usability
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: L10n.string("support.feedback_category_bug", fallback: "不具合")
        case .request: L10n.string("support.feedback_category_request", fallback: "要望")
        case .usability: L10n.string("support.feedback_category_usability", fallback: "使いにくさ")
        case .other: L10n.string("support.feedback_category_other", fallback: "その他")
        }
    }
}

struct FeedbackReportBuilder {
    static func body(
        category: FeedbackCategory,
        message: String,
        appVersion: String,
        operatingSystemVersion: String
    ) -> String {
        L10n.string(
            "support.feedback_report_body",
            fallback: "BodyMode フィードバック\n\n種類: {{value1}}\n内容:\n{{value2}}\n\nアプリ: {{value3}}\nOS: {{value4}}",
            values: [
                category.title,
                message.trimmingCharacters(in: .whitespacesAndNewlines),
                appVersion,
                operatingSystemVersion,
            ]
        )
    }
}

struct InAppFeedbackView: View {
    @Environment(\.openURL) private var openURL
    @State private var category: FeedbackCategory = .bug
    @State private var message = ""
    @State private var includesDiagnostics = true
    @State private var sharePayload: FeedbackSharePayload?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(L10n.string("support.feedback_category_section", fallback: "種類")) {
                Picker(L10n.string("support.feedback_category_picker", fallback: "フィードバックの種類"), selection: $category) {
                    ForEach(FeedbackCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("feedbackMessageEditor")
            } header: {
                Text(L10n.string("support.feedback_details", fallback: "内容"))
            } footer: {
                Text(L10n.string("support.feedback_sensitive_warning", fallback: "身体値、食事内容、写真、AIとの会話、認証情報は記載しないでください。"))
            }

            Section {
                Toggle(L10n.string("support.feedback_attach_diagnostics", fallback: "匿名の診断ログを添付"), isOn: $includesDiagnostics)
                    .accessibilityIdentifier("feedbackDiagnosticsToggle")
            } footer: {
                Text(L10n.string("support.feedback_diagnostics_explanation", fallback: "アプリとApple Watchの動作・通信情報を添付します。身体・健康記録や写真、AI会話は含みません。"))
            }

            Section {
                Button {
                    prepareShare()
                } label: {
                    Label(L10n.string("support.feedback_send", fallback: "フィードバックを送る"), systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("sendInAppFeedbackButton")
            }

            Section(L10n.string("support.feedback_other_ways", fallback: "別の送り方")) {
                Button {
                    UIPasteboard.general.string = reportBody
                } label: {
                    Label(L10n.string("support.feedback_copy_text", fallback: "本文をコピー"), systemImage: "doc.on.doc")
                }
                .disabled(trimmedMessage.isEmpty)
                .accessibilityIdentifier("copyInAppFeedbackButton")

                if let emailURL {
                    Button {
                        openURL(emailURL)
                    } label: {
                        Label(L10n.string("support.feedback_send_email", fallback: "メールで送る"), systemImage: "envelope")
                    }
                    .disabled(trimmedMessage.isEmpty)
                    .accessibilityIdentifier("emailInAppFeedbackButton")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("support.feedback_title", fallback: "フィードバック"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in
            ActivityShareView(activityItems: payload.activityItems)
        }
        .alert(L10n.string("support.feedback_diagnostics_failed", fallback: "診断ログを添付できませんでした"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.string("support.feedback_send_without_diagnostics", fallback: "診断なしで送る")) {
                prepareShare(includeDiagnostics: false)
            }
            Button(L10n.string("support.feedback_retry", fallback: "再試行")) {
                prepareShare()
            }
            Button(L10n.string("support.feedback_cancel", fallback: "キャンセル"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? L10n.string("support.feedback_unknown_error", fallback: "不明なエラー"))
        }
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reportBody: String {
        FeedbackReportBuilder.body(
            category: category,
            message: message,
            appVersion: LegalConfiguration.appVersion,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private var emailURL: URL? {
        guard let supportEmail = LegalConfiguration.supportEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "BodyMode Feedback"),
            URLQueryItem(name: "body", value: reportBody)
        ]
        return components.url
    }

    private func prepareShare(includeDiagnostics override: Bool? = nil) {
        var items: [Any] = [reportBody]

        if override ?? includesDiagnostics {
            do {
                items.append(try AppDiagnostics.shared.makeShareFile())
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        sharePayload = FeedbackSharePayload(activityItems: items)
    }
}

private struct FeedbackSharePayload: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}
