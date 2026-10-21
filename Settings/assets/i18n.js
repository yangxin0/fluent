// Fluent Settings speaks English by default; this is every other language it
// knows. Keys are the English strings as written in index.html and app.js; a
// missing key falls back to English. {name} slots are filled by t(text, vars).
const I18N = {
  zh: {
    // Header
    "Setup": "开始",
    "LLM": "大模型",
    "English": "英文",
    "Chinese": "中文",
    "Appearance": "外观",
    "Advanced": "高级",
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

    // LLM
    "Fluent sends what you type to a language model and shows the improved text in the bar. Keep several providers and switch between them here or in the input method's menu.":
      "Fluent 把你输入的内容发给大模型，并在候选栏里显示改进后的文字。可以保存多个服务商，在这里或输入法菜单里切换。",
    "Providers": "服务商",
    "Add provider": "添加服务商",
    "Provider {n}": "服务商 {n}",
    "In use": "使用中",
    "Use": "使用",
    "Unnamed": "未命名",
    "No model": "未设模型",
    "Name": "名称",
    "API": "接口",
    "Delete": "删除",
    "Delete {name}?": "删除“{name}”？",
    "Its URL, API key and model go with it.": "它的服务地址、API 密钥和模型会一起删除。",
    "A provider needs a name.": "服务商需要一个名称。",
    "Another provider has that name.": "已经有同名的服务商。",
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
    // English
    "How Fluent improves the English you type. Switch modes with Ctrl+Tab or from the input method's menu.":
      "Fluent 如何改进你输入的英文。用 Ctrl+Tab 或输入法菜单切换模式。",
    "Uses {name}, the provider in use.": "使用当前的服务商 {name}。",
    "Prompts": "提示词",
    "Fix": "修正",
    "Polish": "润色",
    "Translate": "翻译",
    "Built-in prompt": "内置提示词",
    "Your own prompt": "自定义提示词",
    "Fluent always adds:": "Fluent 总会在后面加上：",
    "Try": "试一试",
    "Trying…": "正在试…",
    "Reset to default": "恢复默认",
    "Your words": "你的词",
    "Settings most people never need to change.": "多数人用不着改的设置。",
    "Prefix keys": "前缀键",
    "Add": "添加",
    "Remove": "删除",
    "Press a shortcut… (Esc to cancel)": "按下快捷键…（Esc 取消）",
    "Use Control, Option or Command with a key.": "请同时按住 Control、Option 或 Command 中的一个。",
    "After one of these shortcuts, the next key goes straight to the app instead of starting a composition: the N in Ctrl-X N, the c in tmux's Ctrl-B c.":
      "按下这些快捷键之一后，下一个键直接交给 App，不会开始输入：例如 Ctrl-X N 里的 N、tmux 的 Ctrl-B c 里的 c。",
    "Words Fluent keeps in English instead of reading them as pinyin, one per line: product names, jargon. Pressing Enter in the Chinese bar adds the letters you typed.":
      "Fluent 当作英文、不按拼音读的词，每行一个：产品名、术语等。在中文候选栏里按回车，会把你敲的字母加进来。",
    "Timing": "时间",

    // Chinese
    "English always comes first: Chinese converts only when the letters you type can't be English.":
      "英文永远优先：只有你输入的字母不可能是英文时，才会转换成中文。",
    "Input method": "输入方案",
    "全拼(Pinyin)": "全拼",
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
    "How the candidate bar and the ⇧⇧ notice look, and how Fluent treats terminal apps.":
      "候选栏和 ⇧⇧ 提示的外观，以及 Fluent 如何对待终端 App。",
    "Candidate bar": "候选栏",
    "Theme": "主题",
    "Bar size": "候选栏大小",
    "Small": "小",
    "Medium": "中",
    "Large": "大",
    "Text size": "字号",
    "Candidates per page": "每页候选数",
    "Terminals": "终端",
    "Language": "语言",
    "Settings window": "设置窗口",
    "System": "跟随系统",
    "Light": "浅色",
    "Dark": "深色",
    "⇧⇧ notice": "⇧⇧ 提示",
    "Badge": "徽标",
    "Pill": "胶囊",
    "Bubble": "气泡",
    "Bubble + keys": "气泡 + 按键",
    "Shown at the caret for a moment when you double-tap Shift: on, then off.":
      "双击 Shift 时在光标处短暂显示：左为开启，右为关闭。",
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
    "Improves the English you type, and types Chinese with 全拼 or 小鹤双拼.": "改进你输入的英文，并用全拼或小鹤双拼打中文。",
    "Free software under the GPL-3.0. The dictionaries come from rime-ice (GPL-3.0); the Chinese engine ports algorithms from librime (BSD-3-Clause).":
      "以 GPL-3.0 许可发布的自由软件。词库来自 rime-ice（GPL-3.0）；中文引擎移植了 librime 的算法（BSD-3-Clause）。",
    "Open the config file": "打开配置文件",

    // Toasts
    "Saved": "已保存",
    "Couldn't save: the config file isn't valid JSON.": "无法保存：配置文件不是有效的 JSON。",
    "Couldn't save the words.": "无法保存这些词。",
  },
};
