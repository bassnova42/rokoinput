import Foundation

enum RecognitionFailure {
    static func message(_ error: NSError) -> String {
        if error.domain == "kLSRErrorDomain", error.code == 201 {
            return "系统听写已关闭（201）。请在系统设置 → 键盘 → 听写中开启，然后重试。"
        }
        if error.domain == "kLSRErrorDomain", error.code == 102 {
            return "本地语音资源未安装（102）。请先在系统中准备中文听写资源。"
        }
        if error.domain == "kAFAssistantErrorDomain", error.code == 1110 {
            return "未识别到语音（1110）。请检查麦克风，并在录音开始后说话。"
        }
        return "识别失败（\(error.code)）：\(error.localizedDescription) [\(error.domain)]"
    }
}
