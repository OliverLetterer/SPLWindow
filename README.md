# SPLWindow

SPLWindow is a UIWindow subclass with the following features:

- SPLWindow can highlight your touches during AirPlay mirroring.
- Rage shake your device and SPLWindow can take a screenshot of your current visible view hierarchy or record a video of your devices screen. Screenshots can be annotated by drawing on them and video recording happens in real time and can be stopped by tapping the record indicator in the bottom right of your screen.

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
