// Fluent Settings speaks English by default; this is every other language it
// knows. Keys are the English strings as written in index.html and app.js; a
// missing key falls back to English. {name} slots are filled by t(text, vars).
const I18N = {
  zh: {
    // Header
    "Setup": "开始",
    "Rewrite": "改写",
    "Chinese": "中文",
    "Appearance": "外观",
    "About": "关于",

    // Setup
    "Get Fluent ready": "准备好 Fluent",
    "Fluent is an input method: it improves the English you type and types Chinese, right in the app you're using.":
      "Fluent 是一个输入法：在你正在用的任何 App 里，改进你输入的英文，也能打中文。",
    "Input method installed": "输入法已安装",
    "Run make install in the source folder.": "在源码目录运行 make install。",
    "Added in Input Sources": "已添加到输入法列表",
    "System Settings ▸ Keyboard ▸ Input Sources ▸ + ▸ English ▸ Fluent. macOS doesn't let apps add it for you.":
      "系统设置 ▸ 键盘 ▸ 输入法 ▸ + ▸ 英语 ▸ Fluent。macOS 不允许 App 替你添加。",
    "Open Input Sources": "打开输入法设置",
    "Selected": "已选用",
    "Pick Fluent from the input menu in the menu bar, or press Ctrl+Space.":
      "在菜单栏的输入法菜单里选 Fluent，或按 Ctrl+空格。",
    "API key set": "已设置 API 密钥",
    "Needed to improve English. Chinese works without it.": "改进英文时需要；打中文不需要。",
    "Set up": "去设置",
    "Dictionaries present": "词库就绪",
    "make install downloads them from rime-ice.": "make install 会从 rime-ice 下载。",
    "Config error: {problem}": "配置文件有误：{problem}",
    "Double-tap Shift": "连按两下 Shift",
    "turns Fluent on and off, for terminal commands or passwords.": "开关 Fluent，输入终端命令或密码时很方便。",
    "Enter": "回车",
    "inserts the improved text; Shift+Enter inserts it as typed.": "输入改进后的文字；Shift+回车按原样输入。",

    // Rewrite
    "Fluent sends what you type to an OpenAI Responses-compatible API and shows the improved text in the bar.":
      "Fluent 把你输入的内容发给兼容 OpenAI Responses 的接口，并在候选栏里显示改进后的文字。",
    "Provider URL": "服务地址",
    "API key": "API 密钥",
    "Show": "显示",
    "Hide": "隐藏",
    "Model": "模型",
    "Reasoning effort": "推理强度",
    "Model default": "模型默认",
    "Wait after typing": "停顿后请求",
    "Timeout": "超时",
    "The timeout counts how long the reply may stay silent, not its whole length.":
      "超时指回复可以停顿多久，而不是整个回复的时长。",
    "Test": "测试",
    "Testing…": "测试中…",
    "Set the provider URL, API key and model first.": "请先填写服务地址、API 密钥和模型。",

    // Chinese
    "English always comes first: Chinese converts only when the letters you type can't be English.":
      "英文永远优先：只有你输入的字母不可能是英文时，才会转换成中文。",
    "Input method": "输入方案",
    "全拼 (full pinyin)": "全拼",
    "Off": "关闭",
    "Initials only": "简拼",
    "zg → 中国, bj → 北京": "zg → 中国，bj → 北京",
    "Fuzzy pinyin": "模糊音",
    "These apply to 全拼 only.": "仅用于全拼。",
    "Learned words": "已学习的词",
    "{n} words": "{n} 个",
    "Forget learned words": "清除学习记录",
    "Words you pick move ahead of the others, the way Rime learns them.": "你选过的词会排到前面，与 Rime 的学习方式相同。",
    "Forget learned words?": "清除学习记录？",
    "Candidates go back to the dictionary's order. This can't be undone.": "候选词将恢复为词库的顺序。此操作无法撤销。",
    "Forget": "清除",
    "Cancel": "取消",
    "Forgot the learned words": "已清除学习记录",

    // Appearance
    "How the candidate bar looks, and how Fluent treats terminal apps.": "候选栏的外观，以及 Fluent 如何对待终端 App。",
    "Candidate bar": "候选栏",
    "System": "跟随系统",
    "Light": "浅色",
    "Dark": "深色",
    "Settings language": "设置界面语言",
    "Terminal mode": "终端模式",
    "Automatic": "自动",
    "Always": "总是",
    "Never": "从不",
    "Terminals clip text at the window edge, so near it the bar also shows what you typed.":
      "终端会在窗口边缘截断文字，所以快到边缘时候选栏也会显示你输入的内容。",
    "More terminal apps": "更多终端 App",
    "One bundle identifier per line, on top of the built-in list.": "每行一个 Bundle ID，追加到内置列表之后。",
    "Cell width": "字符宽度",

    // About
    "Improves the English you type, and types Chinese with 小鹤双拼 or 全拼.": "改进你输入的英文，并用小鹤双拼或全拼打中文。",
    "Free software under the GPL-3.0. The dictionaries come from rime-ice (GPL-3.0); the Chinese engine ports algorithms from librime (BSD-3-Clause).":
      "以 GPL-3.0 许可发布的自由软件。词库来自 rime-ice（GPL-3.0）；中文引擎移植了 librime 的算法（BSD-3-Clause）。",
    "Open the config file": "打开配置文件",

    // Toasts
    "Saved": "已保存",
    "Couldn't save: the config file isn't valid JSON.": "无法保存：配置文件不是有效的 JSON。",
  },
};
