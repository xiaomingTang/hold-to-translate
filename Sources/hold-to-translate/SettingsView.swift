import AppKit
import SwiftUI

private let integerInputFormatter: NumberFormatter = {
  let formatter = NumberFormatter()
  formatter.numberStyle = .none
  formatter.allowsFloats = false
  formatter.minimum = 0
  return formatter
}()

private enum ThresholdHelp {
  case warn
  case hard

  var title: String {
    switch self {
    case .warn:
      return "警告阈值 说明"
    case .hard:
      return "拒绝阈值 说明"
    }
  }

  var message: String {
    switch self {
    case .warn:
      return "当选中文本长度超过该阈值时，会先弹出确认框，确认后才继续翻译。"
    case .hard:
      return "当选中文本长度超过该阈值时，将直接拒绝翻译，避免超长文本导致耗时或成本升高。"
    }
  }
}

struct LaunchControlView: View {
  @ObservedObject var state: TranslationAppState
  @State private var isAPIKeyHelpPresented = false
  @State private var isWarnThresholdHelpPresented = false
  @State private var isHardThresholdHelpPresented = false

  private let azureTranslatorResourceURL = URL(
    string: "https://learn.microsoft.com/azure/ai-services/translator/create-translator-resource")!

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        GroupBox("辅助功能") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("辅助功能").foregroundStyle(.secondary)
              Spacer()
              Button {
                state.openAccessibilitySettings()
              } label: {
                Text(state.accessibilityStatus.displayName).underline()
              }
              .buttonStyle(.plain)
              .foregroundStyle(state.accessibilityStatus == .granted ? .green : .orange)
              .help("打开辅助功能系统设置")
              Button {
                state.recheckAccessibilityStatus()
              } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
              }
              .buttonStyle(.plain).help("重新检测权限")
            }
            Text(state.lastTriggerStatusMessage).font(.callout).foregroundStyle(.secondary)
          }.padding(.vertical, 4)
        }

        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            Toggle(
              "开机自启动",
              isOn: Binding(get: { state.loginAtLaunchEnabled }, set: state.setLoginAtLaunchEnabled)
            )
            languageRow(
              "目标语言",
              value: Binding(
                get: { state.settings.targetLanguage }, set: { state.settings.targetLanguage = $0 })
            )
            languageRow(
              "备选语言",
              value: Binding(
                get: { state.settings.alternateLanguage },
                set: { state.settings.alternateLanguage = $0 }))
            HStack {
              Text("触发键").foregroundStyle(.secondary)
              Spacer()
              Picker(
                " ",
                selection: Binding(
                  get: { state.settings.triggerButton },
                  set: { state.settings.triggerButton = $0 })
              ) {
                ForEach(TriggerButton.allCases) { Text($0.displayName).tag($0) }
              }
              .pickerStyle(.segmented)
              .frame(width: 220)
            }
            HStack {
              Text("长按时长").foregroundStyle(.secondary)
              Spacer()
              Text("\(Int(state.settings.longPressMilliseconds)) ms")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
              Slider(
                value: Binding(
                  get: { state.settings.longPressMilliseconds },
                  set: { state.settings.longPressMilliseconds = $0 }), in: 200...1200, step: 50
              )
              .frame(width: 180)
            }
            thresholdRow(
              "警告阈值",
              value: Binding(
                get: { state.settings.thresholds.warnLimit },
                set: { state.settings.thresholds.warnLimit = max(1, min(9999, $0)) }),
              help: .warn,
              isHelpPresented: $isWarnThresholdHelpPresented)
            thresholdRow(
              "拒绝阈值",
              value: Binding(
                get: { state.settings.thresholds.hardLimit },
                set: { state.settings.thresholds.hardLimit = max(1, min(20000, $0)) }),
              help: .hard,
              isHelpPresented: $isHardThresholdHelpPresented)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
        } label: {
          Text("应用设置")
        }
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            textFieldRow(
              "Endpoint",
              placeholder: "Endpoint",
              value: Binding(
                get: { state.settings.endpoint }, set: { state.settings.endpoint = $0 }))
            textFieldRow(
              "Region",
              placeholder: "Region",
              value: Binding(get: { state.settings.region }, set: { state.settings.region = $0 }))
            HStack {
              Text("API Key").foregroundStyle(.secondary)
              Spacer()
              SecureField(
                "API Key", text: Binding(get: { state.apiKey }, set: { state.apiKey = $0 })
              )
              .frame(width: 260)
            }
          }
          .padding(.vertical, 4)
        } label: {
          HStack(spacing: 4) {
            Text("API 配置")
            Button {
              isAPIKeyHelpPresented.toggle()
            } label: {
              Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .help("查看 API Key 说明")
            .popover(isPresented: $isAPIKeyHelpPresented, arrowEdge: .bottom) {
              VStack(alignment: .leading, spacing: 10) {
                Text("API Key 说明").font(.headline)
                Text("这里填写的是 Microsoft Azure AI Translator 的 API Key。")
                Text("请在 Azure 门户创建 Translator 资源后，复制该资源的 Key 1 或 Key 2，并同时填写对应的 Region。")
                Link("打开 Azure Translator 官方文档", destination: azureTranslatorResourceURL)
              }
              .frame(width: 320, alignment: .leading)
              .padding(16)
            }
          }
        }
        HStack {
          Spacer()
          Button("退出应用") { NSApp.terminate(nil) }.buttonStyle(.borderedProminent).tint(.red)
        }
      }
    }
    .padding(20)
    .groupBoxStyle(SettingsGroupBoxStyle())
    .onAppear { state.refreshLoginItemStatus() }
  }

  private func textFieldRow(
    _ title: String, placeholder: String, value: Binding<String>
  ) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      TextField(placeholder, text: value).frame(width: 260)
    }
  }

  private func languageRow(_ title: String, value: Binding<String>) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      SearchableLanguageDropdown(options: supportedLanguageOptions, selectedCode: value).frame(
        width: 220)
    }
  }

  private func thresholdRow(
    _ title: String, value: Binding<Int>, help: ThresholdHelp, isHelpPresented: Binding<Bool>
  ) -> some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Button {
        isHelpPresented.wrappedValue.toggle()
      } label: {
        Image(systemName: "questionmark.circle")
      }
      .buttonStyle(.plain)
      .help("查看\(title)说明")
      .popover(isPresented: isHelpPresented, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 10) {
          Text(help.title).font(.headline)
          Text(help.message)
        }
        .frame(width: 300, alignment: .leading)
        .padding(16)
      }
      Spacer()
      TextField(title, value: value, formatter: integerInputFormatter).frame(width: 120)
    }
  }
}

private struct SettingsGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      configuration.label.font(.headline)
      configuration.content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    }
  }
}
