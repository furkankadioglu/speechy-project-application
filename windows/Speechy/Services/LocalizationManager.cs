namespace Speechy.Services;

/// <summary>
/// Provides UI string translations for 8 supported languages.
/// Mirrors macOS LocalizationManager.
/// </summary>
public class LocalizationManager
{
    private static readonly Lazy<LocalizationManager> _instance = new(() => new LocalizationManager());
    public static LocalizationManager Instance => _instance.Value;

    public (string Code, string NativeName, string Flag)[] SupportedLanguages { get; } =
    {
        ("en", "English", "🇬🇧"),
        ("tr", "Türkçe", "🇹🇷"),
        ("pt", "Português", "🇧🇷"),
        ("zh", "中文", "🇨🇳"),
        ("es", "Español", "🇪🇸"),
        ("ru", "Русский", "🇷🇺"),
        ("uk", "Українська", "🇺🇦"),
        ("pl", "Polski", "🇵🇱"),
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
    };
}
