using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Pages;
using SaveStories.WinUI.Beta.Services;

namespace SaveStories.WinUI.Beta;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        BetaSettingsStore.Current.Load();
        ApplyTheme(BetaSettingsStore.Current.Theme);
        BetaSettingsStore.Current.ThemeChanged += OnThemeChanged;
        AppNav.SelectedItem = AppNav.MenuItems[0];
        ContentFrame.Navigate(typeof(StoriesPage));
    }

    private void OnNavigationSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag)
        {
            return;
        }

        switch (tag)
        {
            case "stories":
                ContentFrame.Navigate(typeof(StoriesPage));
                break;
            case "queue":
                ContentFrame.Navigate(typeof(QueuePage));
                break;
            case "reels":
                ContentFrame.Navigate(typeof(ReelsPage));
                break;
            case "settings":
                ContentFrame.Navigate(typeof(SettingsPage));
                break;
        }
    }

    private void OnThemeChanged(object? sender, BetaTheme theme)
    {
        ApplyTheme(theme);
    }

    private void ApplyTheme(BetaTheme theme)
    {
        if (Content is FrameworkElement root)
        {
            root.RequestedTheme = theme == BetaTheme.Light ? ElementTheme.Light : ElementTheme.Dark;
        }
    }
}
