namespace Speechy.Services;

/// <summary>
/// Provides UI string translations for 18 supported languages.
/// Mirrors macOS LocalizationManager.
/// </summary>
public class LocalizationManager
{
    private static readonly Lazy<LocalizationManager> _instance = new(() => new LocalizationManager());
    public static LocalizationManager Instance => _instance.Value;

    public (string Code, string NativeName, string Flag)[] SupportedLanguages { get; } =
    {
        ("en", "English",           "🇬🇧"),
        ("tr", "Türkçe",            "🇹🇷"),
        ("de", "Deutsch",           "🇩🇪"),
        ("fr", "Français",          "🇫🇷"),
        ("es", "Español",           "🇪🇸"),
        ("it", "Italiano",          "🇮🇹"),
        ("pt", "Português",         "🇧🇷"),
        ("nl", "Nederlands",        "🇳🇱"),
        ("pl", "Polski",            "🇵🇱"),
        ("ru", "Русский",           "🇷🇺"),
        ("uk", "Українська",        "🇺🇦"),
        ("zh", "中文",              "🇨🇳"),
        ("ja", "日本語",            "🇯🇵"),
        ("ko", "한국어",             "🇰🇷"),
        ("ar", "العربية",           "🇸🇦"),
        ("hi", "हिन्दी",            "🇮🇳"),
        ("id", "Bahasa Indonesia",  "🇮🇩"),
        ("vi", "Tiếng Việt",        "🇻🇳"),
    };

    public string Loc(string key)
    {
        var lang = SettingsManager.Instance.AppLanguage;
        if (_translations.TryGetValue(lang, out var dict) && dict.TryGetValue(key, out var val))
            return val;
        if (_translations.TryGetValue("en", out var enDict) && enDict.TryGetValue(key, out var enVal))
            return enVal;
        return key;
    }

    private readonly Dictionary<string, Dictionary<string, string>> _translations = new()
    {
        ["en"] = new()
        {
            ["nav.hotkeys"] = "Hot Keys",
            ["nav.advanced"] = "Advanced",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "History",
            ["nav.license"] = "License",
            ["nav.other"] = "Other Settings",
            ["nav.logs"] = "Logs",
            ["nav.quit"] = "Quit",
            ["section.app_language"] = "App Language",
            ["other.language_desc"] = "Select the language for the user interface.",
        },
        ["tr"] = new()
        {
            ["nav.hotkeys"] = "Kısayollar",
            ["nav.advanced"] = "Gelişmiş",
            ["nav.prompt"] = "Komut",
            ["nav.history"] = "Geçmiş",
            ["nav.license"] = "Lisans",
            ["nav.other"] = "Diğer Ayarlar",
            ["nav.logs"] = "Günlükler",
            ["nav.quit"] = "Çıkış",
            ["section.app_language"] = "Uygulama Dili",
            ["other.language_desc"] = "Kullanıcı arayüzü dilini seçin.",
        },
        ["de"] = new()
        {
            ["nav.hotkeys"] = "Tastenkürzel",
            ["nav.advanced"] = "Erweitert",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "Verlauf",
            ["nav.license"] = "Lizenz",
            ["nav.other"] = "Weitere Einst.",
            ["nav.logs"] = "Protokolle",
            ["nav.quit"] = "Beenden",
            ["section.app_language"] = "App-Sprache",
            ["other.language_desc"] = "Wähle die Sprache der Benutzeroberfläche.",
        },
        ["fr"] = new()
        {
            ["nav.hotkeys"] = "Raccourcis",
            ["nav.advanced"] = "Avancé",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "Historique",
            ["nav.license"] = "Licence",
            ["nav.other"] = "Autres réglages",
            ["nav.logs"] = "Journaux",
            ["nav.quit"] = "Quitter",
            ["section.app_language"] = "Langue de l'app",
            ["other.language_desc"] = "Sélectionnez la langue de l'interface.",
        },
        ["es"] = new()
        {
            ["nav.hotkeys"] = "Teclas de Acceso",
            ["nav.advanced"] = "Avanzado",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "Historial",
            ["nav.license"] = "Licencia",
            ["nav.other"] = "Otros Ajustes",
            ["nav.logs"] = "Registros",
            ["nav.quit"] = "Salir",
            ["section.app_language"] = "Idioma de la App",
            ["other.language_desc"] = "Seleccione el idioma de la interfaz.",
        },
        ["it"] = new()
        {
            ["nav.hotkeys"] = "Scorciatoie",
            ["nav.advanced"] = "Avanzate",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "Cronologia",
            ["nav.license"] = "Licenza",
            ["nav.other"] = "Altre impost.",
            ["nav.logs"] = "Log",
            ["nav.quit"] = "Esci",
            ["section.app_language"] = "Lingua app",
            ["other.language_desc"] = "Seleziona la lingua dell'interfaccia.",
        },
        ["pt"] = new()
        {
            ["nav.hotkeys"] = "Teclas de Atalho",
            ["nav.advanced"] = "Avançado",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "Histórico",
            ["nav.license"] = "Licença",
            ["nav.other"] = "Outras Config.",
            ["nav.logs"] = "Registros",
            ["nav.quit"] = "Sair",
            ["section.app_language"] = "Idioma do App",
            ["other.language_desc"] = "Selecione o idioma da interface.",
        },
        ["nl"] = new()
        {
            ["nav.hotkeys"] = "Sneltoetsen",
            ["nav.advanced"] = "Geavanceerd",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "Geschiedenis",
            ["nav.license"] = "Licentie",
            ["nav.other"] = "Overige inst.",
            ["nav.logs"] = "Logboeken",
            ["nav.quit"] = "Stoppen",
            ["section.app_language"] = "App-taal",
            ["other.language_desc"] = "Selecteer de taal van de interface.",
        },
        ["pl"] = new()
        {
            ["nav.hotkeys"] = "Skróty klawiszowe",
            ["nav.advanced"] = "Zaawansowane",
            ["nav.prompt"] = "Podpowiedź",
            ["nav.history"] = "Historia",
            ["nav.license"] = "Licencja",
            ["nav.other"] = "Inne ustawienia",
            ["nav.logs"] = "Dzienniki",
            ["nav.quit"] = "Wyjdź",
            ["section.app_language"] = "Język aplikacji",
            ["other.language_desc"] = "Wybierz język interfejsu użytkownika.",
        },
        ["ru"] = new()
        {
            ["nav.hotkeys"] = "Горячие клавиши",
            ["nav.advanced"] = "Расширенные",
            ["nav.prompt"] = "Подсказки",
            ["nav.history"] = "История",
            ["nav.license"] = "Лицензия",
            ["nav.other"] = "Настройки",
            ["nav.logs"] = "Журналы",
            ["nav.quit"] = "Выйти",
            ["section.app_language"] = "Язык приложения",
            ["other.language_desc"] = "Выберите язык интерфейса.",
        },
        ["uk"] = new()
        {
            ["nav.hotkeys"] = "Гарячі клавіші",
            ["nav.advanced"] = "Розширені",
            ["nav.prompt"] = "Підказки",
            ["nav.history"] = "Історія",
            ["nav.license"] = "Ліцензія",
            ["nav.other"] = "Інші налаштування",
            ["nav.logs"] = "Журнали",
            ["nav.quit"] = "Вийти",
            ["section.app_language"] = "Мова програми",
            ["other.language_desc"] = "Виберіть мову інтерфейсу.",
        },
        ["zh"] = new()
        {
            ["nav.hotkeys"] = "快捷键",
            ["nav.advanced"] = "高级",
            ["nav.prompt"] = "提示词",
            ["nav.history"] = "历史",
            ["nav.license"] = "许可证",
            ["nav.other"] = "其他设置",
            ["nav.logs"] = "日志",
            ["nav.quit"] = "退出",
            ["section.app_language"] = "应用语言",
            ["other.language_desc"] = "选择用户界面语言。",
        },
        ["ja"] = new()
        {
            ["nav.hotkeys"] = "ショートカット",
            ["nav.advanced"] = "詳細設定",
            ["nav.prompt"] = "プロンプト",
            ["nav.history"] = "履歴",
            ["nav.license"] = "ライセンス",
            ["nav.other"] = "その他の設定",
            ["nav.logs"] = "ログ",
            ["nav.quit"] = "終了",
            ["section.app_language"] = "アプリ言語",
            ["other.language_desc"] = "インターフェースの言語を選択してください。",
        },
        ["ko"] = new()
        {
            ["nav.hotkeys"] = "단축키",
            ["nav.advanced"] = "고급",
            ["nav.prompt"] = "프롬프트",
            ["nav.history"] = "기록",
            ["nav.license"] = "라이선스",
            ["nav.other"] = "기타 설정",
            ["nav.logs"] = "로그",
            ["nav.quit"] = "종료",
            ["section.app_language"] = "앱 언어",
            ["other.language_desc"] = "인터페이스 언어를 선택하세요.",
        },
        ["ar"] = new()
        {
            ["nav.hotkeys"] = "اختصارات",
            ["nav.advanced"] = "متقدم",
            ["nav.prompt"] = "موجه",
            ["nav.history"] = "السجل",
            ["nav.license"] = "الترخيص",
            ["nav.other"] = "إعدادات أخرى",
            ["nav.logs"] = "السجلات",
            ["nav.quit"] = "إنهاء",
            ["section.app_language"] = "لغة التطبيق",
            ["other.language_desc"] = "اختر لغة الواجهة.",
        },
        ["hi"] = new()
        {
            ["nav.hotkeys"] = "हॉटकी",
            ["nav.advanced"] = "उन्नत",
            ["nav.prompt"] = "प्रॉम्प्ट",
            ["nav.history"] = "इतिहास",
            ["nav.license"] = "लाइसेंस",
            ["nav.other"] = "अन्य सेटिंग",
            ["nav.logs"] = "लॉग",
            ["nav.quit"] = "बंद करें",
            ["section.app_language"] = "ऐप भाषा",
            ["other.language_desc"] = "इंटरफ़ेस की भाषा चुनें।",
        },
        ["id"] = new()
        {
            ["nav.hotkeys"] = "Pintasan",
            ["nav.advanced"] = "Lanjutan",
            ["nav.prompt"] = "Prompt",
            ["nav.history"] = "Riwayat",
            ["nav.license"] = "Lisensi",
            ["nav.other"] = "Pengaturan Lain",
            ["nav.logs"] = "Log",
            ["nav.quit"] = "Keluar",
            ["section.app_language"] = "Bahasa Aplikasi",
            ["other.language_desc"] = "Pilih bahasa antarmuka.",
        },
        ["vi"] = new()
        {
            ["nav.hotkeys"] = "Phím tắt",
            ["nav.advanced"] = "Nâng cao",
            ["nav.prompt"] = "Gợi nhắc",
            ["nav.history"] = "Lịch sử",
            ["nav.license"] = "Giấy phép",
            ["nav.other"] = "Cài đặt khác",
            ["nav.logs"] = "Nhật ký",
            ["nav.quit"] = "Thoát",
            ["section.app_language"] = "Ngôn ngữ",
            ["other.language_desc"] = "Chọn ngôn ngữ giao diện.",
        },
    };
}
