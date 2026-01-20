using Android.App;
using Android.OS;
using Android.Widget;

namespace NativeAotSample;

[Activity(Label = "NativeAOT Sample", MainLauncher = true)]
public class MainActivity : Activity
{
    protected override void OnCreate(Bundle? savedInstanceState)
    {
        base.OnCreate(savedInstanceState);

        var layout = new LinearLayout(this)
        {
            Orientation = Orientation.Vertical
        };
        layout.SetPadding(50, 50, 50, 50);

        var titleText = new TextView(this)
        {
            Text = "NativeAOT Android Sample",
            TextSize = 24
        };
        layout.AddView(titleText);

        var infoText = new TextView(this)
        {
            Text = $"Runtime: {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription}\n" +
                   $"OS: {System.Runtime.InteropServices.RuntimeInformation.OSDescription}\n" +
                   $"Arch: {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}",
            TextSize = 14
        };
        infoText.SetPadding(0, 30, 0, 30);
        layout.AddView(infoText);

        var button = new Button(this)
        {
            Text = "Click Me!"
        };
        
        int clickCount = 0;
        button.Click += (sender, e) =>
        {
            clickCount++;
            Toast.MakeText(this, $"Clicked {clickCount} time(s)!", ToastLength.Short)?.Show();
        };
        layout.AddView(button);

        SetContentView(layout);

        Android.Util.Log.Info("NativeAotSample", "APP_STARTED_SUCCESSFULLY");
    }
}
