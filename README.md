# SPLWindow

SPLWindow is a UIWindow subclass with the following features:

- Touch highlighting during AirPlay mirroring.
- Rage shake to take a screenshot: Screenshots can be annotated and send via mail.
- Rage shake to record video: Record a video right on your device in real time at full fps and send it via mail.
- Rage shake to show and edit [Tweaks](https://github.com/facebook/Tweaks).

## Warning

SPLWindow uses private APIs for screen recording, so make sure that this __doesn't ship in your AppStore version__.

## Installation

```ruby
pod 'SPLWindow', '~> 1.0'
```

## Usage

``` objc
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	// !!! Make sure this doesn't ship in production
	self.window = [[SPLWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rageShakeEnabled = YES;
	self.window.highlightsTouchesDuringAirPlayMirroring = YES;
	self.window.highlightsTouchesDuringScreenRecording = YES;
	
	return YES;
}
```

## Contact
Oliver Letterer

- http://github.com/OliverLetterer
- http://twitter.com/oletterer

## License
SPLWindow is available under the MIT license. See the LICENSE file for more information.
