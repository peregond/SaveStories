namespace SaveMe.WinUI.Beta.Services;

public static class TimeOfDayThemeService
{
    public const int DayStartsAtHour = 7;
    public const int NightStartsAtHour = 19;

    public static BetaTheme Resolve(DateTimeOffset localTime)
    {
        return localTime.Hour >= DayStartsAtHour && localTime.Hour < NightStartsAtHour
            ? BetaTheme.Light
            : BetaTheme.Dark;
    }
}
