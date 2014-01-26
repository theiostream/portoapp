/* PortoApp
 iOS interface to the Colégio Visconde de Porto Seguro grade/news etc.
 
 Created by Daniel Ferreira in 9/09/2013
 (c) 2013 Bacon Coding Company, LLC
 no rights whatsoever to the Fundação Visconde de Porto Seguro
 
 Licensed under the GNU General Public License version 3.
 Because I don't want my work stolen.
 */

// Tips!
// [23:41:33] <@DHowett> theiostream: At the top of the function, get 'self.bounds' out into a local variable. each time you call it is a dynamic dispatch because the compiler cannot assume that it has no side-effects
// [23:42:13] <@DHowett> theiostream: the attributed strings and their CTFrameshit should be cached whenver possible. do not create a new attributed string every time the rect is drawn

/* Credits {{{

Personal thanks:
- Dustin Howett
- Guilherme (Lima) Stark
- Lucas Zamprogno
- Max Shavrick
- Natham Coracini 

Project Thanks:
- HNKit (session design inspiration)
- MobileCydia.mm (goes without saying)

Code taken from third parties:
- XMLDocument, XMLElement were reproduced from Grant Paul (chpwn)'s HNKit.
(c) 2011 Xuzz Productions LLC

- LoginController, LoadingIndicatorView were changed minorly from Grant Paul (chpwn)'s news:yc.
(c) 2011 Xuzz Productions LLC

- KeychainItemWrapper was reproduced from Apple's GenericKeychain sample project.
(c) 2010 Apple Inc.

- ABTableViewCell was reproduced from enormego's github repo.
(c) 2008 Loren Brichter

- GTMNSStringHTMLAdditions category was taken from google-toolbox-for-mac.
(c) 2006-2008 Google Inc.

}}} */

/* Include {{{ */
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

#include "viewstate/viewstate.h"
/* }}} */

/* External {{{ */

#import "External.mm"

/* }}} */

/* Macros {{{ */

#define SYSTEM_VERSION_GT_EQ(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

#define NUMBER_YES [NSNumber numberWithBool:YES]
#define NUMBER_NO [NSNumber numberWithBool:NO]

#ifdef DEBUG
#define debug(...) NSLog(__VA_ARGS__)
#else
#define debug(...)
#endif

// A Macro created on IRC by Maximus!
// I don't get shifts nor other bitwise operations.
#define UIColorFromHexWithAlpha(rgbValue,a) \
	[UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
		green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
		blue:((float)(rgbValue & 0xFF))/255.0 \
		alpha:a]

// Thanks to http://stackoverflow.com/questions/139655/convert-pixels-to-points
#define pxtopt(px) ( px * 72 / 96 )
#define pttopx(pt) ( pt * 96 / 72 )

#define MAKE_CORETEXT_CONTEXT(context) \
	CGContextRef context = UIGraphicsGetCurrentContext(); \
	CGContextSetTextMatrix(context, CGAffineTransformIdentity); \
	CGContextTranslateCTM(context, 0, self.bounds.size.height); \
	CGContextScaleCTM(context, 1.0, -1.0);

#define AmericanLocale [NSLocale localeWithLocaleIdentifier:@"en_US"]

/* }}} */

/* Helpers {{{ */
// This is usually either quick functions written by me or stuff taken from StackOverflow :)

/* URL Encoding {{{ */
// Written by theiostream
static NSString *NSStringURLEncode(NSString *string) {
	return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)string, NULL, CFSTR("!*'();:@&;=+$,/%?#[]"), kCFStringEncodingUTF8) autorelease];
}

static NSString *NSStringURLDecode(NSString *string) {
	return [(NSString *)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL, (CFStringRef)string, CFSTR(""), kCFStringEncodingUTF8) autorelease];
}
/* }}} */

/* Unescaping HTML {{{ */
// Found on StackOverflow.
static NSString *RemoveHTMLTags(NSString *content) {
	NSString *newString = [[content copy] autorelease];
	
	NSRange range;
	while ((range = [newString rangeOfString:@"<[^>]+>" options:NSRegularExpressionSearch]).location != NSNotFound)
		newString = [newString stringByReplacingCharactersInRange:range withString:@""];
	
	return newString;
}
/* }}} */

/* News {{{ */
static NSString *ParseNewsParagraph(NSString *paragraph) {
	NSString *unescaped = [RemoveHTMLTags(paragraph) gtm_stringByUnescapingFromHTML];
	return unescaped;
}
/* }}} */

/* Caching {{{ */
// A pretty lame cache written by theiostream
static NSMutableDictionary *cache = nil;
static inline void InitCache() { cache = [[NSMutableDictionary alloc] init]; }
static inline id Cached(NSString *key) { return [cache objectForKey:key]; }
static inline void Cache(NSString *key, id object) { [cache setObject:object forKey:key]; }

/* }}} */

/* Pair {{{ */
// Pair class written by theiostream

@interface Pair : NSObject {
@public
	id obj1;
	id obj2;
}
- (id)initWithObjects:(id)object, ...;
@end

@implementation Pair
- (id)initWithObjects:(id)object, ... {
	if ((self = [super init])) {
		va_list args;
		va_start(args, object);
		
		obj1 = [object retain];
		obj2 = [va_arg(args, id) retain];
		va_end(args);
	}

	return self;
}

- (void)dealloc {
	[obj1 release];
	[obj2 release];

	[super dealloc];
}
@end

/* }}} */

/* CoreText {{{ */
// CoreText helpers written by theiostream

/* Some history on these functions:
./2013-09-18.txt:[18:11:35] <@theiostream> i'm using coretext
./2013-09-18.txt:[19:23:51] <@theiostream> and Maximus, all made in coretext ;)
./2013-09-18.txt:[19:32:55] <@theiostream> Maximus: coretext doesn't let me
./2013-09-27.txt:[23:14:50] <@theiostream> i need to draw shit with coretext
./2013-09-27.txt:[23:15:03] <@theiostream> since i need to spin the context to draw coretext
./2013-09-27.txt:[23:16:47] <Maximus_> coretext is ok

./2013-09-01.txt:[16:37:47] <@DHowett> fucking coretext
*/

static CFAttributedStringRef CreateBaseAttributedString(CTFontRef font, CGColorRef textColor, CFStringRef string, BOOL underlined = NO, CTLineBreakMode lineBreakMode = kCTLineBreakByWordWrapping, CTTextAlignment alignment = kCTLeftTextAlignment)  {
	if (string == NULL) string = (CFStringRef)@"";
	
	CGFloat spacing = 0.f;
	CTParagraphStyleSetting settings[3] = {
		{ kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(CGFloat), &spacing },
		{ kCTParagraphStyleSpecifierLineBreakMode, sizeof(CTLineBreakMode), &lineBreakMode },
		{ kCTParagraphStyleSpecifierAlignment, sizeof(CTTextAlignment), &alignment }
	};
	CTParagraphStyleRef paragraphStyle = CTParagraphStyleCreate(settings, 3);
	
	int underline = underlined ? 1 : kCTUnderlineStyleNone;
	CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &underline);

	const CFStringRef attributeKeys[4] = { kCTFontAttributeName, kCTForegroundColorAttributeName, kCTParagraphStyleAttributeName, kCTUnderlineStyleAttributeName };
	const CFTypeRef attributeValues[4] = { font, textColor, paragraphStyle, number };
	CFDictionaryRef attributes = CFDictionaryCreate(NULL, (const void **)attributeKeys, (const void **)attributeValues, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

	CFAttributedStringRef attributedString = CFAttributedStringCreate(NULL, string, attributes);
	CFRelease(attributes);
	CFRelease(number);
	CFRelease(paragraphStyle);

	return attributedString;
}

static CTFramesetterRef CreateFramesetter(CTFontRef font, CGColorRef textColor, CFStringRef string, BOOL underlined, CTLineBreakMode lineBreakMode = kCTLineBreakByWordWrapping, CTTextAlignment alignment = kCTLeftTextAlignment) {
	CFAttributedStringRef attributedString = CreateBaseAttributedString(font, textColor, string, underlined, lineBreakMode, alignment);
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(attributedString);
	CFRelease(attributedString);

	return framesetter;
}

static CTFrameRef CreateFrame(CTFramesetterRef framesetter, CGRect rect) {
	CGPathRef path = CGPathCreateWithRect(rect, NULL);
	CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, NULL);

	CFRelease(path);
	return frame;
}

static void DrawFramesetter(CGContextRef context, CTFramesetterRef framesetter, CGRect rect) {
	CTFrameRef frame = CreateFrame(framesetter, rect);
	CTFrameDraw(frame, context);
	CFRelease(frame);
}

/* }}} */

/* Colors {{{ */
// Taken from StackOverflow

// I wrote this!
// (and finally put bitwise operation knowledge to use)
/*#define MixColorHex 0x8FD8D8
static uint32_t GetNiceColor(int rr, int rg, int rb) {
	int r = (rr + ((MixColorHex & 0xff0000) >> 16)) / 2;
	int g = (rg + ((MixColorHex & 0xff00) >> 8)) / 2;
	int b = (rb + (MixColorHex & 0xff)) / 2;
	
	return ((r & 0xff) << 16) + ((g & 0xff) << 8) + (b & 0xff);	
}

static uint32_t RandomColorHex() {
	// commentout
	int rr = arc4random_uniform(256);
	int rg = arc4random_uniform(256);
	int rb = arc4random_uniform(256);

	int rr = arc4random() % 256;
	int rg = arc4random() % 256;
	int rb = arc4random() % 256;
	
	return GetNiceColor(rr, rg, rb);
}*/

static uint32_t Colors[64] = { 0x000000,0x00FF00,0x0000FF,0xFF0000,0x01FFFE,0xFFA6FE,0xFFDB66,0x006401,0x010067,0x95003A,0x007DB5,0xFF00F6,0xFFEEE8,0x774D00,0x90FB92,0x0076FF,0xD5FF00,0xFF937E,0x6A826C,0xFF029D,0xFE8900,0x7A4782,0x7E2DD2,0x85A900,0xFF0056,0xA42400,0x00AE7E,0x683D3B,0xBDC6FF,0x263400,0xBDD393,0x00B917,0x9E008E,0x001544,0xC28C9F,0xFF74A3,0x01D0FF,0x004754,0xE56FFE,0x788231,0x0E4CA1,0x91D0CB,0xBE9970,0x968AE8,0xBB8800,0x43002C,0xDEFF74,0x00FFC6,0xFFE502,0x620E00,0x008F9C,0x98FF52,0x7544B1,0xB500FF,0x00FF78,0xFF6E41,0x005F39,0x6B6882,0x5FAD4E,0xA75740,0xA5FFD2,0xFFB167,0x009BFF,0xE85EBE };
static uint32_t RandomColorHex() {
	return Colors[arc4random_uniform(64)];
}

static UIColor *ColorForGrade(CGFloat grade, BOOL graded = YES) {
	UIColor *color;
	
	if (grade < 6) color = graded ? UIColorFromHexWithAlpha(0xFF3300, 1.f) : UIColorFromHexWithAlpha(0xC75F5F, 1.f);
	else if (grade < 8) color = graded ? UIColorFromHexWithAlpha(0xFFCC00, 1.f) : UIColorFromHexWithAlpha(0xC7A15F, 1.f);
	else color = graded ? UIColorFromHexWithAlpha(0x33CC33, 1.f) : UIColorFromHexWithAlpha(0x5FA4C7, 1.f);
	
	return color;
}

/* }}} */

/* Image Resizing {{{ */

// From StackOverflow. Dude, how this answer has saved my ass so many times.
static UIImage *UIImageResize(UIImage *image, CGSize newSize) {
	UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
	[image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
	UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();    
	UIGraphicsEndImageContext();
	
	return newImage;
}

/* }}} */

/* Fix View Bounds {{{ */
// I hate iOS 7.
// Like, everything was fine and then Apple decides to do whatever the shitfuck they're thinking to the bounding system.

// Thanks to http://iphonedevsdk.com/forum/iphone-sdk-development/7953-height-of-standard-navbar-tabbar-statusbar.html
#define HEIGHT_OF_STATUSBAR 20.f
#define HEIGHT_OF_NAVBAR 44.f
#define HEIGHT_OF_TABBAR 50.f

#define HEIGHT_WITH_TABBARCONTROLLER ([[UIScreen mainScreen] applicationFrame].size.height - HEIGHT_OF_NAVBAR - HEIGHT_OF_TABBAR)

static CGRect PerfectFrameForViewController(UIViewController *self) {
	CGRect ret = [[UIScreen mainScreen] bounds];
	
	if (SYSTEM_VERSION_GT_EQ(@"7.0")) {
		ret.origin.y += HEIGHT_OF_STATUSBAR;
		ret.size.height -= HEIGHT_OF_STATUSBAR;

		if ([self navigationController]) {
			ret.origin.y += HEIGHT_OF_NAVBAR;
			ret.size.height -= HEIGHT_OF_NAVBAR;
		}
	}
	else {
		ret.size.height -= HEIGHT_OF_STATUSBAR;

		if ([self navigationController])
			ret.size.height -= HEIGHT_OF_NAVBAR;
	}

	if ([self tabBarController]) {
		ret.size.height -= HEIGHT_OF_TABBAR;
	}
	
	ret.size.height += 1.f;
	return ret;
	
	/*CGRect ret = [[UIScreen mainScreen] applicationFrame];
	ret.origin.y -= HEIGHT_OF_STATUSBAR;
	ret.size.height += HEIGHT_OF_STATUSBAR;
	return ret;*/

	//return [[UIScreen mainScreen] applicationFrame];
}

static inline CGRect FrameWithNavAndTab() {
	CGRect bounds = [[UIScreen mainScreen] bounds];
	return CGRectMake(bounds.origin.x, bounds.origin.y + HEIGHT_OF_STATUSBAR + HEIGHT_OF_NAVBAR, bounds.size.width, bounds.size.height - HEIGHT_OF_STATUSBAR - HEIGHT_OF_NAVBAR - HEIGHT_OF_TABBAR + 1.f);
}

static CGRect FixViewBounds(CGRect bounds) {
	if (SYSTEM_VERSION_GT_EQ(@"7.0")) bounds.origin.y += HEIGHT_OF_STATUSBAR + HEIGHT_OF_NAVBAR;
	bounds.size.height = HEIGHT_WITH_TABBARCONTROLLER + 1.f;

	return bounds;
}

/* }}} */

/* Cool Button Delay Scroll View {{{ */
// Taken from http://stackoverflow.com/questions/3642547/uibutton-touch-is-delayed-when-in-uiscrollview

#define kNoDelayButtonTag 77

@interface NoButtonDelayScrollView : UIScrollView
@end

@implementation NoButtonDelayScrollView
- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		[self setDelaysContentTouches:NO];
	}

	return self;
}

- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
	if ([view isKindOfClass:[UIButton class]]) return YES;
	return [super touchesShouldCancelInContentView:view];
}
@end

@interface NoButtonDelayTableView : UITableView
@end

@implementation NoButtonDelayTableView
- (id)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
	if ((self = [super initWithFrame:frame style:style])) {
		[self setDelaysContentTouches:NO];
	}

	return self;
}

- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
	if ([view isKindOfClass:[UIButton class]]) return YES;
	return [super touchesShouldCancelInContentView:view];
}
@end

/* }}} */

/* Circulares <a> tag {{{ */

static NSString *GetATagContent(NSString *aTag) {
	NSLog(@"aTag is %@", aTag);
        
        NSRange r1 = [aTag rangeOfString:@">"];
	NSRange r2 = [aTag rangeOfString:@"<" options:0 range:NSMakeRange(r1.location + r1.length, [aTag length]-(r1.location + r1.length))];
	NSRange r = NSMakeRange(r1.location + r1.length, r2.location - r1.location - r1.length);
	
	return [[aTag substringWithRange:r] stringByDeletingPathExtension];
}

static NSString *GetATagHref(NSString *aTag) {
	NSScanner *scanner = [NSScanner scannerWithString:aTag];
	[scanner scanUpToString:@"href" intoString:NULL];
	[scanner setScanLocation:[scanner scanLocation] + 6];

	NSString *link;
	[scanner scanUpToString:@"'" intoString:&link]; // replace ' with " and this becomes general-purpose
	
	return link;
}

/* }}} */

/* }}} */

/* Constants {{{ */

#define kPortoRootURL @"http://www.portoseguro.org.br/"
#define kPortoRootCircularesPage @"http://www.circulares.portoseguro.org.br/"

/* }}} */

/* Categories {{{ */

@interface NSDictionary (PortoURLEncoding)
- (NSString *)urlEncodedString;
@end

@implementation NSDictionary (PortoURLEncoding)
- (NSString *)urlEncodedString {
	NSMutableString *ret = [NSMutableString string];
	
	NSArray *allKeys = [self allKeys];
	for (NSString *key in allKeys) {
		[ret appendString:NSStringURLEncode(key)];
		[ret appendString:@"="];
		[ret appendString:NSStringURLEncode([self objectForKey:key])];
		[ret appendString:@"&"];
	}
	
	return [ret substringToIndex:[ret length]-1];
}
@end

@interface NSString (AmericanFloat)
- (NSString *)americanFloat;
- (BOOL)isGrade;
@end

@implementation NSString (AmericanFloat)
- (NSString *)americanFloat {
	return [self stringByReplacingOccurrencesOfString:@"," withString:@"."];
}

- (BOOL)isGrade {
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+[\\.,]\\d+" options:0 error:NULL];
	return [regex numberOfMatchesInString:self options:0 range:NSMakeRange(0, [self length])] > 0;
}
@end

/* }}} */

/* Classes {{{ */

/* Sessions {{{ */

typedef void (^SessionAuthenticationHandler)(NSArray *, NSString *, NSError *);

@interface SessionAuthenticator : NSObject <NSURLConnectionDataDelegate> {
	NSString *$username;
	NSString *$password;
	
	NSURLConnection *$connection;
	SessionAuthenticationHandler $handler;
}
- (SessionAuthenticator *)initWithUsername:(NSString *)username password:(NSString *)password;
- (void)authenticateWithHandler:(SessionAuthenticationHandler)handler;
@end

@interface SessionController : NSObject {
	KeychainItemWrapper *$keychainItem;
	KeychainItemWrapper *$gradeKeyItem;
	KeychainItemWrapper *$papersKeyItem;

	NSDictionary *$accountInfo;
	NSString *$gradeID;
	NSString *$papersID;
	
	NSDictionary *$sessionInfo;
}
+ (SessionController *)sharedInstance;

- (NSDictionary *)accountInfo;
- (void)setAccountInfo:(NSDictionary *)secInfo;
- (BOOL)hasAccount;

- (NSString *)gradeID;
- (void)setGradeID:(NSString *)gradeID;

- (NSString *)papersID;
- (void)setPapersID:(NSString *)papersID;

- (NSDictionary *)sessionInfo;
- (void)setSessionInfo:(NSDictionary *)sessionInfo;
- (BOOL)hasSession;

- (void)loadSessionWithHandler:(void(^)(BOOL, NSError *))handler;
- (NSData *)loadPageWithURL:(NSURL *)url method:(NSString *)method response:(NSURLResponse **)response error:(NSError **)error;
@end

/* }}} */

/* Views {{{ */

/* Pie Chart View {{{ */

@class GradeContainer;
@class PieChartView;

// i don't like iOS 7
@interface PickerActionSheet : UIView {
	PieChartView *$pieChartView;
	UILabel *$subtitleLabel;
}
- (id)initWithHeight:(CGFloat)height pieChartView:(PieChartView *)pieChartView;
- (void)display;
- (void)dismiss;
- (void)setSubtitleLabelText:(NSString *)text;
@end

#define deg2rad(deg) (deg * (M_PI/180.f))
#define rad2deg(rad) (rad * (180.f/M_PI))
#define kPickerViewHeight 216.f

@interface PieChartPiece : NSObject
@property(nonatomic, assign) CGFloat percentage;
@property(nonatomic, retain) GradeContainer *container;
@property(nonatomic, assign) uint32_t color;
@property(nonatomic, retain) NSString *text;
@property(nonatomic, retain) CALayer *layer;
@property(nonatomic, assign) BOOL isBonus;
@end

// TODO: Better implementation.
// God, please tell me I am a bad programmer and that there is a better way to do this
// Why did you implement UISlider like this, Apple? Why do size changes need to be image-based
// instead of being built-in? Why, Apple, why?!
@interface PieChartSliderViewSlider : UISlider @end

@protocol PieChartSliderViewDelegate;
@interface PieChartSliderView : UIView {
	PieChartPiece *$piece;
	PieChartSliderViewSlider *$slider;
}

@property(nonatomic, assign) id<PieChartSliderViewDelegate> delegate;
- (UISlider *)slider;

- (PieChartPiece *)piece;
- (id)initWithFrame:(CGRect)frame piece:(PieChartPiece *)piece;
@end

@protocol PieChartSliderViewDelegate <NSObject>
@optional
- (void)pieChartSliderView:(PieChartSliderView *)sliderView didSlideWithValue:(float)value;
@end

@protocol PieChartViewDelegate;
@interface PieChartView : UIView <PieChartSliderViewDelegate, UIPickerViewDelegate, UIPickerViewDataSource> {
	PieChartPiece *$emptyPiece;
	NSMutableArray *$pieces;
	CGFloat $radius;

	NSInteger $percentageSum;
	
	UIButton *$addGradeButton;
	PickerActionSheet *$pickerSheet;
	NSInteger *$rowMap;
	NSInteger $selectedContainerType;
}
@property(nonatomic, assign) id<PieChartViewDelegate> delegate;
+ (CGFloat)extraHeight;
- (id)initWithFrame:(CGRect)frame pieces:(NSArray *)pieces count:(NSUInteger)count radius:(CGFloat)radius emptyPiece:(PieChartPiece *)empty;
- (void)updateBonusSliders;
@end

@protocol PieChartViewDelegate <NSObject>
@required
@optional
- (void)pieChartView:(PieChartView *)view didSelectPiece:(PieChartPiece *)piece;
@end

/* }}} */

/* Loading Indicator View {{{ */

@interface LoadingIndicatorView : UIView {
    UIActivityIndicatorView *spinner_;
    UILabel *label_;
    UIView *container_;
}

@property (readonly, nonatomic) UILabel *label;
@property (readonly, nonatomic) UIActivityIndicatorView *activityIndicatorView;
@end

/* }}} */

/* Fail Views {{{ */

@interface FailView : UIView {
	UIView *centerView;
	UIImageView *imageView;
	UILabel *label;
}
@property(nonatomic, retain) NSString *text;
@property(nonatomic, retain) UIImage *image;
@end

/* }}} */

/* }}} */

/* Controllers {{{ */

/* Web Data Controller {{{ */

@interface WebDataViewController : UIViewController {
	dispatch_queue_t $queue;

	LoadingIndicatorView *$loadingView;
	FailView *$failureView;
	UIView *$contentView;
}

- (WebDataViewController *)initWithIdentifier:(NSString *)identifier;

- (UIView *)contentView;
- (void)loadContentView;
- (void)unloadContentView;

- (void)refresh;
- (void)reloadData;

- (void)$freeViews;
- (void)freeData;

- (void)displayLoadingView;
- (void)hideLoadingView;
- (void)displayFailViewWithImage:(UIImage *)img text:(NSString *)text;
- (void)displayContentView;

- (void)$performUIBlock:(void(^)())block;
@end

/* }}} */

/* Web View Controller {{{ */

@interface WebViewController : UIViewController <UIWebViewDelegate>
- (void)loadPage:(NSString *)page;
- (void)loadURL:(NSURL *)url;
- (void)loadLocalFile:(NSString *)file;
- (NSString *)executeJavascript:(NSString *)javascript;

/* UIWebView {{{ */

@property(nonatomic,assign) id<UIWebViewDelegate> delegate;

@property(nonatomic,readonly,retain) UIScrollView *scrollView NS_AVAILABLE_IOS(5_0);

- (void)loadRequest:(NSURLRequest *)request;
- (void)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL;
- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL;

@property(nonatomic,readonly,retain) NSURLRequest *request;

- (void)reload;
- (void)stopLoading;

- (void)goBack;
- (void)goForward;

@property(nonatomic,readonly,getter=canGoBack) BOOL canGoBack;
@property(nonatomic,readonly,getter=canGoForward) BOOL canGoForward;
@property(nonatomic,readonly,getter=isLoading) BOOL loading;

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;

@property(nonatomic) BOOL scalesPageToFit;

@property(nonatomic) BOOL detectsPhoneNumbers NS_DEPRECATED_IOS(2_0, 3_0);
@property(nonatomic) UIDataDetectorTypes dataDetectorTypes NS_AVAILABLE_IOS(3_0);

@property (nonatomic) BOOL allowsInlineMediaPlayback NS_AVAILABLE_IOS(4_0); // iPhone Safari defaults to NO. iPad Safari defaults to YES
@property (nonatomic) BOOL mediaPlaybackRequiresUserAction NS_AVAILABLE_IOS(4_0); // iPhone and iPad Safari both default to YES

@property (nonatomic) BOOL mediaPlaybackAllowsAirPlay NS_AVAILABLE_IOS(5_0); // iPhone and iPad Safari both default to YES

@property (nonatomic) BOOL suppressesIncrementalRendering NS_AVAILABLE_IOS(6_0); // iPhone and iPad Safari both default to NO

@property (nonatomic) BOOL keyboardDisplayRequiresUserAction NS_AVAILABLE_IOS(6_0); // default is YES

@property (nonatomic) UIWebPaginationMode paginationMode NS_AVAILABLE_IOS(7_0);
@property (nonatomic) UIWebPaginationBreakingMode paginationBreakingMode NS_AVAILABLE_IOS(7_0);
@property (nonatomic) CGFloat pageLength NS_AVAILABLE_IOS(7_0);
@property (nonatomic) CGFloat gapBetweenPages NS_AVAILABLE_IOS(7_0);
@property (nonatomic, readonly) NSUInteger pageCount NS_AVAILABLE_IOS(7_0);

/* }}} */

- (UIWebView *)webView;
@end

/* }}} */

/* Login Controller {{{ */

@protocol LoginControllerDelegate;

@interface LoginController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate> {
	id<LoginControllerDelegate> $delegate;
	
	UIImageView *$backgroundImageView;
	UIView *$tableContainerView;
	UIView *$centeringAlignmentView;
    
	UITableView *$tableView;
    
	UITableViewCell *$usernameCell;
	UITableViewCell *$passwordCell;
	UITableViewCell *$loadingCell;
    
	UITextField *$usernameField;
	UITextField *$passwordField;
	
	UIImageView *$topImageView;
	UILabel *$bottomLabel;
    
	UIBarButtonItem *$cancelItem;
	UIBarButtonItem *$completeItem;
    
	BOOL $isAuthenticating;
}

@property (nonatomic, assign) id<LoginControllerDelegate> delegate;
- (void)sendRequest;
- (void)endRequestWithSuccess:(BOOL)success error:(NSError *)error;

- (void)authenticate;
- (NSArray *)gradientColors;
@end

@protocol LoginControllerDelegate <NSObject>
@optional
- (void)loginControllerDidLogin:(LoginController *)controller;
- (void)loginControllerDidCancel:(LoginController *)controller;
@end

@interface PortoLoginController : LoginController
@end

/* }}} */

/* News {{{ */

@interface NewsTableViewCell : ABTableViewCell {
	UIImage *$newsImage;
	NSString *$newsTitle;
	NSString *$newsSubtitle;
}

@property(nonatomic, retain) UIImage *newsImage;
@property(nonatomic, retain) NSString *newsTitle;
@property(nonatomic, retain) NSString *newsSubtitle;
@end

@interface NewsIndexViewController : UIViewController
@end

@interface NewsItemView : UIView {
	CGSize sectionSize;
	CGSize titleSize;
	CGSize subtitleSize;
	
	CGColorRef textColor;
	CTFontRef sectionFont;
	CTFontRef titleFont;
	CTFontRef subtitleFont;
	CTFontRef bodyFont;

	CTFramesetterRef sectionFramesetter;
	CTFramesetterRef titleFramesetter;
	CTFramesetterRef subtitleFramesetter;
	
	NSArray *contents;
	CTFramesetterRef *bodyFramesetters;
	NSUInteger bodyFramesettersCount;
	NSUInteger imagesCount;
	NSMutableArray *bodySizes;
}
- (CGFloat)heightOffset;
- (void)setSection:(NSString *)section;
- (void)setTitle:(NSString *)title;
- (void)setSubtitle:(NSString *)subtitle;
- (void)setContents:(NSArray *)contents;
@end

@interface NewsItemViewController : UIViewController <UIWebViewDelegate> {
	NSURL *$url;
	
	BOOL $isLoading;

	LoadingIndicatorView *$loadingView;
	UIScrollView *$scrollView;
	NewsItemView *$contentView;
	UIWebView *$webView;
}
@end

@interface NewsViewController : UITableViewController {
	UITableView *$tableView;
	UITableViewCell *$loadingCell;
	
	NSMutableArray *$imageData;
	BOOL $isLoading;
}
@end

/* }}} */

/* Grades {{{ */

#define kPortoAverage 60

@interface GradeContainer : NSObject
@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSString *grade;
@property(nonatomic, retain) NSString *value;
@property(nonatomic, retain) NSString *average;
@property(nonatomic, assign) NSInteger weight;

@property(nonatomic, retain) NSMutableArray *subGradeContainers;
@property(nonatomic, retain) NSMutableArray *subBonusContainers;
@property(nonatomic, retain) GradeContainer *superContainer;

@property(nonatomic, assign) BOOL isBonus;
@property(nonatomic, assign) NSUInteger section;

- (NSInteger)totalWeight;
- (BOOL)isAboveAverage;

- (void)makeValueTen;

- (NSString *)gradePercentage;
- (void)calculateGradeFromSubgrades;
- (void)calculateAverageFromSubgrades;
- (NSInteger)indexAtSupercontainer;
- (float)gradeInSupercontainer;
- (float)$gradePercentage;

@property(nonatomic, assign) NSInteger debugLevel;
@end

@interface TestView : UIView {
}
@property(nonatomic, retain) GradeContainer *container;
- (void)drawDataZoneRect:(CGRect)rect textColor:(CGColorRef)textColor dataFont:(CTFontRef)dataFont boldFont:(CTFontRef)boldFont inContext:(CGContextRef)context;
@end

@interface SubjectTableHeaderView : TestView
@end
@interface SubjectTableViewCellContentView : TestView
@end
@interface SubjectBonusTableHeaderView : TestView <UITextFieldDelegate> {
	UITextField *$textField;
}
@end

@interface SubjectView : UIView <UITableViewDataSource, UITableViewDelegate, PieChartViewDelegate> {
	GradeContainer *$container;
}
- (id)initWithFrame:(CGRect)frame container:(GradeContainer *)container;
@end

@interface GradesListViewController : WebDataViewController {
	NSString *$year;
	NSString *$period;
	NSString *$viewState;
	NSString *$eventValidation;

	GradeContainer *$rootContainer;
}

- (GradesListViewController *)initWithYear:(NSString *)year period:(NSString *)period viewState:(NSString *)viewState eventValidation:(NSString *)eventValidation;
@property (nonatomic, retain) NSString *year;
@property (nonatomic, retain) NSString *period;

- (void)prepareContentView;
@end

@interface GradesLegacyListViewController : UIViewController {
	
}
@end

@interface GradesViewController : WebDataViewController <UITableViewDelegate, UITableViewDataSource> {
	NSMutableDictionary *$periodOptions;
	NSMutableArray *$yearOptions;

	NSString *$viewState;
	NSString *$eventValidation;
}
@end

/* }}} */

/* Papers {{{ */

@interface PapersViewController : WebDataViewController <UITableViewDelegate, UITableViewDataSource> {
	vsType *$viewState;
	vsType *$folder;
}
@end

/* }}} */

/* Services {{{ */

@interface ServicesViewController : UITableViewController
@end

/* }}} */

/* Account {{{ */

@interface AccountViewController : UIViewController <LoginControllerDelegate>
- (void)popupLoginController;
@end

/* }}} */

/* }}} */

/* App Delegate {{{ */

@interface AppDelegate : NSObject <UIApplicationDelegate> {
	UIWindow *$window;
	UITabBarController *$tabBarController;
}
@end

/* }}} */

/* }}} */

/* Implementation {{{ */

/* Views {{{ */

/* Loading Indicator View {{{ */

@implementation LoadingIndicatorView
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        [self setBackgroundColor:[UIColor whiteColor]];

	container_ = [[UIView alloc] init];
        [container_ setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin];
        
        spinner_ = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [spinner_ startAnimating];
        [container_ addSubview:spinner_];
        
        label_ = [[UILabel alloc] init];
        [label_ setFont:[UIFont systemFontOfSize:17.0f]];
        [label_ setBackgroundColor:[UIColor clearColor]];
        [label_ setTextColor:[UIColor grayColor]];
        // [label_ setShadowColor:[UIColor whiteColor]];
        // [label_ setShadowOffset:CGSizeMake(0, 1)];
        [label_ setText:@"Loading..."];
        [container_ addSubview:label_];
        
        [self addSubview:container_];
    } return self;
}

- (void)layoutSubviews {
	NSLog(@"LAYOUT SUBVIEWS");
	[super layoutSubviews];

        CGSize viewsize = [self bounds].size;
        CGSize spinnersize = [spinner_ bounds].size;
        CGSize textsize = [[label_ text] sizeWithFont:[label_ font]];
        float bothwidth = spinnersize.width + textsize.width + 5.0f;
        
        CGRect containrect = {
            CGPointMake(floorf((viewsize.width / 2) - (bothwidth / 2)), floorf((viewsize.height / 2) - (spinnersize.height / 2))),
            CGSizeMake(bothwidth, spinnersize.height)
        };
	NSLog(@"containrect: %@", NSStringFromCGRect(containrect));
        CGRect textrect = {
            CGPointMake(spinnersize.width + 5.0f, floorf((spinnersize.height / 2) - (textsize.height / 2))),
            textsize
        };
        CGRect spinrect = {
            CGPointZero,
            spinnersize
        };
        
        [container_ setFrame:containrect];
        [spinner_ setFrame:spinrect];
        [label_ setFrame:textrect];	
}

- (void)dealloc {
    [spinner_ release];
    [label_ release];
    [container_ release];
    
    [super dealloc];
}

- (UILabel *)label {
    return label_;
}

- (UIActivityIndicatorView *)activityIndicatorView {
    return spinner_;
}
@end

/* }}} */

/* Fail Views {{{ */

@implementation FailView
@synthesize text, image;

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		[self setBackgroundColor:[UIColor redColor]];

		centerView = [[UIView alloc] initWithFrame:CGRectZero];
		[centerView setBackgroundColor:[UIColor yellowColor]];
		
		imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
		[centerView addSubview:imageView];
		[imageView release];
		
		label = [[UILabel alloc] initWithFrame:CGRectZero];
		[centerView addSubview:label];
		[label release];

		[self addSubview:centerView];
		[centerView release];
	}

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
    
	CGSize textSize = [text sizeWithFont:[UIFont systemFontOfSize:13.f] constrainedToSize:CGSizeMake(centerView.bounds.size.width, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];

    
	// draw
}

- (void)dealloc {
	[text release];
	[image release];

	//[centerView release];

	[super dealloc];
}
@end

/* }}} */

// URGENT FIXME: Don't have repeated views. Maybe reuse at least the PickerActionSheet?

/* Pie Chart View {{{ */

#define kPickerActionSheetSpaceAboveBottom 5.f
@implementation PickerActionSheet
- (id)initWithHeight:(CGFloat)height pieChartView:(PieChartView *)pieChartView {
        UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
        if ((self = [super initWithFrame:CGRectMake(5.f, [keyWindow bounds].size.height, [keyWindow bounds].size.width - 10.f, height)])) {
		$pieChartView = pieChartView;

		[self setBackgroundColor:[UIColor whiteColor]];
		[[self layer] setMasksToBounds:NO];
		[[self layer] setCornerRadius:8];

		UIPickerView *pickerView = [[UIPickerView alloc] initWithFrame:CGRectMake(0.f, HEIGHT_OF_NAVBAR, [self bounds].size.width, height - HEIGHT_OF_NAVBAR)];
		[pickerView setDelegate:pieChartView];
		[pickerView setDataSource:pieChartView];
		[pickerView setShowsSelectionIndicator:YES];
		[pickerView setTag:55];
		[self addSubview:pickerView];
		[pickerView release];
		
		UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.f, 0.f, [self bounds].size.width, 2*HEIGHT_OF_NAVBAR/3)];
		[titleLabel setFont:[UIFont systemFontOfSize:pxtopt(HEIGHT_OF_NAVBAR/2)]];
		[titleLabel setTextColor:[UIColor blackColor]];
		[titleLabel setBackgroundColor:[UIColor clearColor]];
		[titleLabel setText:@"Adicionar Nota"];
		[titleLabel setTextAlignment:NSTextAlignmentCenter];
		[self addSubview:titleLabel];
		[titleLabel release];
		
		$subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.f, 2*HEIGHT_OF_NAVBAR/3 - 5.f, [self bounds].size.width, HEIGHT_OF_NAVBAR/3)];
		[$subtitleLabel setFont:[UIFont systemFontOfSize:pxtopt(HEIGHT_OF_NAVBAR/3)]];
		[$subtitleLabel setTextColor:[UIColor blackColor]];
		[$subtitleLabel setBackgroundColor:[UIColor clearColor]];
		[$subtitleLabel setText:@"Selecione o peso."];
		[$subtitleLabel setTextAlignment:NSTextAlignmentCenter];
		[self addSubview:$subtitleLabel];

		UISegmentedControl *doneButton = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObject:@"OK"]];
		[doneButton setMomentary:YES];
		[doneButton setSegmentedControlStyle:UISegmentedControlStyleBar];
		[doneButton setTintColor:[UIColor blackColor]];
		[doneButton setFrame:CGRectMake([self bounds].size.width - 55.f, 7.f, 50.f, 30.f)]; // FIXME?
		[doneButton addTarget:pieChartView action:@selector(doneWithPickerView:) forControlEvents:UIControlEventValueChanged];
		[self addSubview:doneButton];
		[doneButton release];

		UISegmentedControl *cancelButton = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObject:@"Cancel"]];
		[cancelButton setMomentary:YES];
		[cancelButton setSegmentedControlStyle:UISegmentedControlStyleBar];
		[cancelButton setTintColor:[UIColor blackColor]];
		[cancelButton setFrame:CGRectMake(5.f, 7.f, 50.f, 30.f)]; // FIXME?
		[cancelButton addTarget:self action:@selector($dismiss:) forControlEvents:UIControlEventValueChanged];
		[self addSubview:cancelButton];
		[cancelButton release];

		[keyWindow addSubview:self];
	}

	return self;
}

- (void)setSubtitleLabelText:(NSString *)text {
	[$subtitleLabel setText:text];
}

- (void)display {
	UIView *subjectView = $pieChartView;
	while (![subjectView isKindOfClass:[SubjectView class]]) subjectView = [subjectView superview];
	[subjectView setUserInteractionEnabled:NO];

	UIView *endarkenView = [[UIView alloc] initWithFrame:[[[UIApplication sharedApplication] keyWindow] bounds]];
	[endarkenView setBackgroundColor:[UIColor blackColor]];
	[endarkenView setAlpha:0.f];
	[endarkenView setTag:66];
	[[[UIApplication sharedApplication] keyWindow] insertSubview:endarkenView belowSubview:self];
	
	[UIView animateWithDuration:.5f animations:^{
		[endarkenView setAlpha:.5f];
		[self setFrame:(CGRect){{[self frame].origin.x, [self frame].origin.y - kPickerActionSheetSpaceAboveBottom - [self frame].size.height}, [self frame].size}];
	} completion:^(BOOL finished){
		if (finished) [endarkenView release];
	}];
}

- (void)$dismiss:(id)sender { [self dismiss]; }
- (void)dismiss {
	UIView *subjectView = $pieChartView;
	while (![subjectView isKindOfClass:[SubjectView class]]) subjectView = [subjectView superview];
	[subjectView setUserInteractionEnabled:YES];
	
	UIView *endarkenView = [[[UIApplication sharedApplication] keyWindow] viewWithTag:66];
	
	[UIView animateWithDuration:.5f animations:^{
		[self setFrame:CGRectMake([self frame].origin.x, [self frame].origin.y + kPickerActionSheetSpaceAboveBottom + [self frame].size.height, [self frame].size.width, [self frame].size.height)];
		[endarkenView setAlpha:0.f];
	} completion:^(BOOL finished){
		[endarkenView removeFromSuperview];
	}];
}

- (void)dealloc {
	[$subtitleLabel release];
	[super dealloc];
}
@end

@implementation PieChartPiece
@synthesize percentage, container, color, text, layer, isBonus;

- (void)dealloc {
	[container release];
	[text release];
	[layer release];
	[super dealloc];
}
@end

// For some reason, changing the track rect gets you some weird, unpleasant effect on non-retina devices.
@implementation PieChartSliderViewSlider
- (CGRect)trackRectForBounds:(CGRect)bounds {
	return CGRectMake(bounds.origin.x + 5.f, 2.5f, bounds.size.width - 10.f, 9.f);
}

- (CGRect)thumbRectForBounds:(CGRect)bounds trackRect:(CGRect)rect value:(float)value {
	CGRect superRect = [super thumbRectForBounds:bounds trackRect:rect value:value];
	return CGRectMake(superRect.origin.x, 0.f, 15.f, 15.f);
}
@end

#define PieChartSliderView_DiffWidth 48.f
@implementation PieChartSliderView
@synthesize delegate;

- (id)initWithFrame:(CGRect)frame piece:(PieChartPiece *)piece {
	if ((self = [super initWithFrame:frame])) {
		$piece = [piece retain];
		
		// thanks to https://github.com/0xced/iOS-Artwork-Extractor
		// let's hope we don't get in trouble with apple for redisting these images.
		UIImage *knobImage = UIImageResize([UIImage imageNamed:@"UISliderHandle.png"], CGSizeMake(15.f, 15.f));
		UIImage *knobPressedImage = UIImageResize([UIImage imageNamed:@"UISliderHandleDown.png"], CGSizeMake(15.f, 15.f));

		// FIXME: Frame constants!
		UIColor *color = UIColorFromHexWithAlpha([piece color], 1.f);
		$slider = [[PieChartSliderViewSlider alloc] initWithFrame:CGRectMake(0.f, 20.f, [self bounds].size.width - PieChartSliderView_DiffWidth, 15.f)];
		[$slider setThumbImage:knobImage forState:UIControlStateNormal];
		[$slider setThumbImage:knobPressedImage forState:UIControlStateHighlighted];
		[$slider setMinimumTrackTintColor:color];
		
		[$slider setValue:[[[$piece container] grade] floatValue] / [[[$piece container] value] floatValue]]; // fuck.
		[$slider addTarget:self action:@selector(sliderDidSlide:) forControlEvents:UIControlEventValueChanged];
		
		[self addSubview:$slider];
	}

	return self;
}

- (UISlider *)slider {
	return $slider;
}

- (void)sliderDidSlide:(UISlider *)slider {
	[self setNeedsDisplay];
	[[self delegate] pieChartSliderView:self didSlideWithValue:[slider value]];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesEnded:touches withEvent:event];

	UITouch *touch = [touches anyObject];
	CGPoint location = [touch locationInView:self];
	if (CGRectContainsPoint(CGRectMake([self bounds].size.width - PieChartSliderView_DiffWidth, 0.f, PieChartSliderView_DiffWidth, [self bounds].size.height), location)) {
		[$slider setValue:[[[$piece container] grade] floatValue] / [[[$piece container] value] floatValue] animated:YES];
		[self sliderDidSlide:$slider];
	}
}

- (PieChartPiece *)piece {
	return $piece;
}

- (void)drawRect:(CGRect)rect {
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextTranslateCTM(context, 0, self.bounds.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	
	[[UIColor whiteColor] setFill];
	CGContextFillRect(context, rect);
	
	[UIColorFromHexWithAlpha(0xd8d8d8, 1.f) setFill];
	CGContextFillRect(context, CGRectMake(0.f, 0.f, rect.size.width, 1.f));
	
	CGColorRef textColor = [[UIColor blackColor] CGColor];
	NSString *systemFont = [[UIFont systemFontOfSize:1.f] fontName];
	CTFontRef dataFont = CTFontCreateWithName((CFStringRef)systemFont, pxtopt(rect.size.height/2), NULL);
	CTFontRef boldFont = CTFontCreateCopyWithSymbolicTraits(dataFont, pxtopt(rect.size.height/2), NULL, kCTFontBoldTrait, kCTFontBoldTrait);
	
	CTFramesetterRef nameFramesetter = CreateFramesetter(dataFont, textColor, (CFStringRef)[$piece text], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	DrawFramesetter(context, nameFramesetter, CGRectMake(0.f, 15.f, rect.size.width - PieChartSliderView_DiffWidth, 25.f));
	CFRelease(nameFramesetter);
	
	//CGFloat diff = -(([[[$piece container] grade] floatValue] - [$slider value]*10.f) * [[[$piece container] value] floatValue]/10.f); wtf daniel (seriously, wtf daniel)
	CGFloat diff = ([$slider value]*[[[$piece container] value] floatValue]) - [[[$piece container] grade] floatValue];
	CTFramesetterRef changeFramesetter = CreateFramesetter(dataFont, textColor, (CFStringRef)[NSString stringWithFormat:@"%s%.1f", diff>=0?"+":"", diff], NO, kCTLineBreakByTruncatingTail, kCTRightTextAlignment);
	DrawFramesetter(context, changeFramesetter, CGRectMake(rect.size.width - PieChartSliderView_DiffWidth + 5.f, 0.f, PieChartSliderView_DiffWidth - 10.f, rect.size.height/2));
	CFRelease(changeFramesetter);
	CTFramesetterRef gradeFramesetter = CreateFramesetter(boldFont, textColor, (CFStringRef)[NSString stringWithFormat:@"%.2f", [$slider value]*[[[$piece container] value] floatValue]], NO, kCTLineBreakByTruncatingTail, kCTRightTextAlignment);
	DrawFramesetter(context, gradeFramesetter, CGRectMake(rect.size.width - PieChartSliderView_DiffWidth + 5.f, rect.size.height/2, PieChartSliderView_DiffWidth - 10.f, rect.size.height/2));
	CFRelease(gradeFramesetter);
	
	CFRelease(dataFont);
	CFRelease(boldFont);
}

- (void)dealloc {
	[$piece release];
	[$slider release];
	[super dealloc];
}
@end

#define kPieChartViewInset 5.f
#define kGradeTotalFontSize 22.f

@implementation PieChartView
+ (CGFloat)rowHeight {
	return 40.f;
}

+ (CGFloat)extraHeight {
	return 12.f;
}

+ (CGFloat)minHeightForRadius:(CGFloat)radius {
	return radius*2 + kPieChartViewInset*3 + kGradeTotalFontSize + [self extraHeight];
}

- (id)initWithFrame:(CGRect)frame pieces:(NSArray *)pieces count:(NSUInteger)count radius:(CGFloat)radius emptyPiece:(PieChartPiece *)empty {
	if ((self = [super initWithFrame:frame])) {
		$pieces = [pieces mutableCopy];
		$emptyPiece = [empty retain];
		$radius = radius;
		$rowMap = (NSInteger *)calloc(2, sizeof(NSInteger));
		$selectedContainerType = 0;
		
		NSLog(@"INITIALIZING VIEW");
		CGFloat totalAngle = 0.f;
		
		CGFloat firstPercentageSum = 0;
		for (PieChartPiece *piece in pieces) {
			if (firstPercentageSum + [piece percentage] > 100) {
				// we do this so an unshown bonus grade doesn't fuck up the cool centralized angle.
				totalAngle += deg2rad(-((100-firstPercentageSum) * 360.f / 100.f));
				break;
			}

			CGFloat angle = deg2rad(-([piece percentage] * 360.f / 100.f));
			totalAngle += angle;

			firstPercentageSum += [piece percentage];
		}
		
		CGPoint center = CGPointMake(($radius*2 + kPieChartViewInset*2)/2, ($radius*2 + kPieChartViewInset*2)/2);
		
		CGFloat startAngle = totalAngle/2;
		CGFloat percentageSum = 0;
		
		CGFloat pieChartSliderOrigin = 2.f;
		for (PieChartPiece *piece in pieces) {			
			CGFloat percentage = [piece isBonus] && percentageSum+[piece percentage]>100 ? 100-percentageSum : [piece percentage];
			CGFloat deg = percentage * 360.f / 100.f; // TODO: Make this radians already?
			
			CGMutablePathRef path = CGPathCreateMutable();
			CGPathMoveToPoint(path, NULL, center.x, center.y);
			CGPathAddArc(path, NULL, center.x, center.y, $radius, startAngle, startAngle + deg2rad(deg), false);
			startAngle += deg2rad(deg);

			CAShapeLayer *layer = [[CAShapeLayer alloc] init];
			[layer setPath:path];
			[layer setFillColor:[UIColorFromHexWithAlpha(piece.color, 1.f) CGColor]];
			[[self layer] addSublayer:layer];
			[piece setLayer:layer];
			[layer release];

			CGPathRelease(path);
			percentageSum += percentage;

			PieChartSliderView *sliderView = [[PieChartSliderView alloc] initWithFrame:CGRectMake(kPieChartViewInset*3 + $radius*2, pieChartSliderOrigin, [self bounds].size.width - (kPieChartViewInset*3 + $radius*2), 40.f) piece:piece];
			pieChartSliderOrigin += [[self class] rowHeight];
			[sliderView setDelegate:self];
			[self addSubview:sliderView];
			[sliderView release];
		}
		$percentageSum = percentageSum;

		if ($emptyPiece != nil && percentageSum < 100) {
			[$emptyPiece setPercentage:100.f - percentageSum];
			CGFloat deg = [empty percentage] * 360.f / 100.f;
			
			CGMutablePathRef path = CGPathCreateMutable();
			CGPathMoveToPoint(path, NULL, center.x, center.y);
			CGPathAddArc(path, NULL, center.x, center.y, radius, startAngle, startAngle + deg2rad(deg), false);
			startAngle += deg2rad(deg);
			
			CAShapeLayer *layer = [[CAShapeLayer alloc] init];
			[layer setPath:path];
			[layer setFillColor:[UIColorFromHexWithAlpha([empty color], 1.f) CGColor]];
			[[self layer] addSublayer:layer];
			[empty setLayer:layer];
			[layer release];

			CGPathRelease(path);
		}
		
		$addGradeButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
		[$addGradeButton setFrame:CGRectMake(kPieChartViewInset*3 + $radius*2, pieChartSliderOrigin + 2.f, ([self bounds].size.width - (kPieChartViewInset*3 + $radius*2)), [[self class] extraHeight])];
		[[$addGradeButton titleLabel] setFont:[UIFont systemFontOfSize:pxtopt([[self class] extraHeight])]];
		[$addGradeButton setTitle:@"Adicionar Nota" forState:UIControlStateNormal];
		[$addGradeButton setBackgroundColor:[UIColor clearColor]];
		[$addGradeButton setTitleColor:[$addGradeButton tintColor] forState:UIControlStateNormal];
		[$addGradeButton setTitleShadowColor:[UIColor blackColor] forState:UIControlStateHighlighted];
		[$addGradeButton addTarget:self action:@selector(thisIsACoolMethodButIAmSadIAlsoLoveMaximusAndCris:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:$addGradeButton];
		
		$pickerSheet = [[PickerActionSheet alloc] initWithHeight:260.f pieChartView:self];
	}

	return self;
}

- (void)$addContainer:(GradeContainer *)container {
	PieChartPiece *piece = [[[PieChartPiece alloc] init] autorelease];
	[piece setPercentage:[container isBonus] ? [[container grade] floatValue]/[[container value] floatValue] : [container gradeInSupercontainer] * 10.f];
	[piece setContainer:container];
	[piece setColor:RandomColorHex()];
	[piece setText:[container name]];
	[piece setIsBonus:[container isBonus]];
	
	CAShapeLayer *layer = [[CAShapeLayer alloc] init];
	[layer setFillColor:[UIColorFromHexWithAlpha([piece color], 1.f) CGColor]];
	[[self layer] addSublayer:layer];
	[piece setLayer:layer];
	[layer release];
	
	CGFloat pieChartSliderOrigin = [$pieces count] * [[self class] rowHeight];
	PieChartSliderView *sliderView = [[PieChartSliderView alloc] initWithFrame:CGRectMake(kPieChartViewInset*3 + $radius*2, pieChartSliderOrigin, [self bounds].size.width - (kPieChartViewInset*3 + $radius*2), 40.f) piece:piece];
	pieChartSliderOrigin += [[self class] rowHeight];
	[sliderView setDelegate:self];
	[self addSubview:sliderView];
	[sliderView release];
	
	NSUInteger firstBonusIndex = 0;
	for (PieChartPiece *piece_ in $pieces) { if ([piece_ isBonus]) { break; } firstBonusIndex++; }
	
	// This is important because when calculating the 'extra-bonus' thing we must be sure that
	// bonuses are always the last pieces (at least internally).
	[$pieces insertObject:piece atIndex:firstBonusIndex];
	[self updateBonusSliders];

	//[self pieChartSliderView:sliderView didSlideWithValue:0.f];
	
	// URGENT FIXME: There is an insidious bug with this UIButton's tap area positioning etc.
	[$addGradeButton setFrame:CGRectMake(kPieChartViewInset*3 + $radius*2, pieChartSliderOrigin + 2.f, ([self bounds].size.width - (kPieChartViewInset*3 + $radius*2)), [[self class] extraHeight])];
	
	// Partly thanks to http://davidjhinson.wordpress.com/2009/03/24/resizing-a-uitableviews-tableheaderview/
	// I swear, you need to do this *exactly* like this else shit will happen.
	// Don't touch this.
	[self setFrame:(CGRect){[self frame].origin, {[self frame].size.width, MAX(pieChartSliderOrigin + [[self class] extraHeight] + kPieChartViewInset*2, [[self class] minHeightForRadius:$radius])}}];
	UITableView *tableView = (UITableView *)self;
	while (![tableView isKindOfClass:[UITableView class]]) tableView = (UITableView *)[tableView superview];
	[[tableView tableFooterView] setFrame:[self frame]];
	[tableView setTableFooterView:[tableView tableFooterView]];
}

- (void)updateBonusSliders {
	NSArray *subviews = [self subviews];
	for (PieChartSliderView *slider in subviews) {
		if (![slider isKindOfClass:[PieChartSliderView class]]) continue;
		
		//if ([[slider piece] isBonus]) {
			[[slider slider] setValue:[[[[slider piece] container] grade] floatValue] / [[[[slider piece] container] value] floatValue] animated:YES];
			[slider sliderDidSlide:[slider slider]];
		//}
	}
}

- (void)pieChartSliderView:(PieChartSliderView *)sliderView didSlideWithValue:(float)value {
	PieChartPiece *sliderPiece = [sliderView piece];
	if ([sliderPiece isBonus])
		[sliderPiece setPercentage:value * [[[sliderPiece container] value] floatValue] * 10.f];
	else
		[sliderPiece setPercentage:value * [[[sliderPiece container] value] floatValue] * [[sliderPiece container] weight] / [[[sliderPiece container] superContainer] totalWeight] * 10.f];

	CGFloat totalAngle = 0.f;
	CGFloat firstPercentageSum = 0;
	for (PieChartPiece *piece in $pieces) {
		if (firstPercentageSum+[piece percentage] > 100) {
			totalAngle += deg2rad(-((100-firstPercentageSum) * 360.f / 100.f));
			break;
		}

		CGFloat angle = deg2rad(-([piece percentage] * 360.f / 100.f));
		totalAngle += angle;
		
		firstPercentageSum += [piece percentage];
	}
	
	CGPoint center = CGPointMake(($radius*2 + kPieChartViewInset*2)/2, ($radius*2 + kPieChartViewInset*2)/2);
	
	CGFloat startAngle = totalAngle/2;
	CGFloat percentageSum = 0;
	
	for (PieChartPiece *piece in $pieces) {
		CGFloat percentage = [piece isBonus] && percentageSum+[piece percentage]>100 ? 100-percentageSum : [piece percentage];
		CGFloat deg = percentage * 360.f / 100.f; // TODO: Make this radians already?

		CGMutablePathRef path = CGPathCreateMutable();
		CGPathMoveToPoint(path, NULL, center.x, center.y);
		CGPathAddArc(path, NULL, center.x, center.y, $radius, startAngle, startAngle + deg2rad(deg), false);
		startAngle += deg2rad(deg);

		CAShapeLayer *layer = (CAShapeLayer *)[piece layer];
		[layer setPath:path];
		CGPathRelease(path);

		percentageSum += percentage;
	}
	$percentageSum = percentageSum;

	[$emptyPiece setPercentage:100.f - percentageSum];
	CGFloat deg = [$emptyPiece percentage] * 360.f / 100.f;

	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, center.x, center.y);
	CGPathAddArc(path, NULL, center.x, center.y, $radius, startAngle, startAngle + deg2rad(deg), false);
	[(CAShapeLayer *)[$emptyPiece layer] setPath:path];
	CGPathRelease(path);

	[self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
	/* Fundação Visconde de Porto Seguro rage {{{
	So, since I'm about to implement the total/circle thing for the pie chart view (which is nice), I should write this up.
	Today, 4th of December 2013, I went to my school for the Pedagogic Day, where we were meant to discuss how parents
	and students could have a bigger part at school decisions.

	What happened:
	- Two days prior, Director Admir, who had been at our school for 28 years (my age * 2) was fired. Out of the blue. Due to mere "reorganization of the Diretoria".
        - This "reorganization" thing pretty much isolates Valinhos from São Paulo.
	- This day, two B-Zug teachers were fired for no reason at all.
	- After a promise this wouldn't be done until further discussion, wires for cameras are being installed in our classrooms.

	This is here to show how screwed-up our school direction is.
	Because it has become a corporation.
	Run by the four businessmen in suits who sit in a room in São Paulo: the Fundação Visconde de Porto Seguro.

	If I ever sell this app's codebase to them, I'd find it good that they actually see this.
	But that's not happening :P
	 }}} */

	MAKE_CORETEXT_CONTEXT(context);
	[[UIColor whiteColor] setFill];
	CGContextFillRect(context, rect);
	
	[UIColorFromHexWithAlpha(0xd8d8d8, 1.f) setFill];
	CGContextFillRect(context, CGRectMake(0.f, rect.size.height - 1.5f, rect.size.width, 1.5f));
	
	CGFloat grade = $percentageSum / 10.f;
	CGFloat width = kPieChartViewInset * 2 + $radius * 2;
	
	CGColorRef textColor = [[UIColor blackColor] CGColor];
	NSString *systemFont = [[UIFont systemFontOfSize:1.f] fontName];
	CTFontRef font = CTFontCreateWithName((CFStringRef)systemFont, pxtopt(kGradeTotalFontSize), NULL);
	
	CTFramesetterRef framesetter = CreateFramesetter(font, textColor, (CFStringRef)[NSString stringWithFormat:@"%.2f", grade], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRelease(font);
	CGSize requirement = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
	
	CGFloat xOrigin = width/2 - (20.f + 5.f + requirement.width)/2;

	UIColor *color = ColorForGrade(grade);
        [color setFill];
	CGContextFillEllipseInRect(context, CGRectMake(xOrigin, kPieChartViewInset, 20.f, 20.f));
	
	DrawFramesetter(context, framesetter, CGRectMake(xOrigin + 20.f + 5.f, kPieChartViewInset - 1.5f, requirement.width, kGradeTotalFontSize));
	CFRelease(framesetter);
}

- (void)thisIsACoolMethodButIAmSadIAlsoLoveMaximusAndCris:(UIButton *)button {
	[$pickerSheet display];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
	return 2;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
	return component==0 ? 2 : ($selectedContainerType == 0 ? 10 : 100);
}

- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component {
	return 44.f;
}

- (CGFloat)pickerView:(UIPickerView *)pickerView widthForComponent:(NSInteger)component {
	return [pickerView bounds].size.width/2;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
	if (component == 0) {
		return row==0 ? @"Nota" : @"Bônus";
	}

	if ($selectedContainerType == 0) return [NSString stringWithFormat:@"%d", row + 1];
	return [NSString stringWithFormat:@"%.2f", (float)((row + 1)/10.f)];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
	if (component == 0) {
		$selectedContainerType = row;
		[pickerView reloadComponent:1];

		[$pickerSheet setSubtitleLabelText:[@"Selecione o " stringByAppendingString:row==0 ? @"peso." : @"valor."]];
	}
	else $rowMap[$selectedContainerType] = row;
}

- (void)doneWithPickerView:(UISegmentedControl *)sender {
	[$pickerSheet dismiss];
	
	GradeContainer *container = [[[GradeContainer alloc] init] autorelease];
	[container setWeight:$selectedContainerType == 1 ? -1 : ($rowMap[0] + 1)];
	[container setValue:$selectedContainerType == 1 ? [NSString stringWithFormat:@"%.2f", ($rowMap[1] + 1)/10.f] : @"10.00"];
	[container setIsBonus:$selectedContainerType == 1];
	[container setGrade:@"$NoGrade"];
	[container setAverage:@"$NoGrade"];
	[container setName:[NSString stringWithFormat:@"%@ (%@ %@)", $selectedContainerType==1 ? @"Bônus" : @"Nota", $selectedContainerType==1 ? @"Valor" : @"Peso", $selectedContainerType==0 ? [NSString stringWithFormat:@"%d", [container weight]] : [container value]]];
	
	GradeContainer *superContainer = [[[$pieces objectAtIndex:0] container] superContainer];
	[$selectedContainerType==1 ? ([superContainer subBonusContainers]) : ([superContainer subGradeContainers]) addObject:container];
	[container setSuperContainer:[[[$pieces objectAtIndex:0] container] superContainer]];
	
	[self $addContainer:container];

	$rowMap[0] = 0;
	$rowMap[1] = 0;
	$selectedContainerType = 0;
}

- (void)dealloc {
	[$emptyPiece release];
	[$pieces release];
	[$pickerSheet release];
	[$addGradeButton release];

	free($rowMap);

	[super dealloc];
}
@end

/* }}} */

/* }}} */

/* Sessions {{{ */

/* Constants {{{ */

#define kPortoErrorDomain @"PortoServerError"

#define kPortoLoginURL @"http://www.educacional.com.br/login/login_ver.asp"

#define kPortoLoginUsernameKey @"strLogin"
#define kPortoLoginPasswordKey @"strSenha"
#define kPortoLoginErrorRedirect @"/login/errologin.asp"

#define kPortoGenderCookie @"Sexo"
#define kPortoGradeCookie @"Serie"
#define kPortoNameCookie @"Nome"
#define kPortoServerIdCookie @"SessionMan%5FServerId"
#define kPortoSessionIdCookie @"SessionMan%5FSessionId"
#define kPortoASPSessionCookie @"ASPSESSIONID"

#define kPortoUsernameKey @"PortoUsernameKey"
#define kPortoPasswordKey @"PortoPasswordKey"

#define kPortoPortalKey @"PortoPortalKey"
#define kPortoCookieNameKey @"PortoCookieNameKey"
#define kPortoCookieKey @"PortoCookieKey"
#define kPortoNameKey @"PortoNameKey"
#define kPortoGradeKey @"PortoGradeKey"
#define kPortoGenderKey @"PortoGenderKey"
#define kPortoSessionIdKey @"PortoSessionIdKey"
#define kPortoServerIdKey @"PortoServerIdKey"

#define kPortoInfantilPortal @"/ed_infantil_new/ed_infantil.asp"
#define kPortoNivelIPortal @"/alunos14/alunos14.asp"
#define kPortoNivelIIPortal @"/alunos58/alunos58.asp"
#define kPortoEMPortal @"/alunos13/alunos13.asp"
#define kPortoGeneralPortal @"/alunos.asp"

/* }}} */

/* Session Authenticator {{{ */

@implementation SessionAuthenticator
- (SessionAuthenticator *)initWithUsername:(NSString *)username password:(NSString *)password {
	if ((self = [super init])) {
		$username = [username retain];
		$password = [password retain];
		
		$connection = nil;
		$handler = nil;
	}

	return self;
}

- (void)endConnection {
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
	
	[$connection release];
	$connection = nil;

	[$handler release];
	$handler = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	$handler(nil, nil, [NSError errorWithDomain:@"PortoServerError" code:-1 userInfo:nil]);
	[self endConnection];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	$handler(nil, nil, error);
	[self endConnection];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
	if (response == nil) return request;

	if (response != nil) {
		NSDictionary *headerFields = [(NSHTTPURLResponse *)response allHeaderFields];
		NSString *location = [headerFields objectForKey:@"Location"];
        
		if ([location hasPrefix:kPortoLoginErrorRedirect]) {
			$handler(nil, nil, [NSError errorWithDomain:kPortoErrorDomain code:1 userInfo:nil]);
		}
		else if ([location hasPrefix:kPortoGeneralPortal] || [location hasPrefix:kPortoInfantilPortal] || [location hasPrefix:kPortoNivelIPortal] || [location hasPrefix:kPortoNivelIIPortal] || [location hasPrefix:kPortoEMPortal]) {
			NSLog(@"GOOD PORTAL!");
			$handler([NSHTTPCookie cookiesWithResponseHeaderFields:headerFields forURL:[response URL]], location, nil);
		}
		else {
			NSLog(@"BAD PORTAL %@", location);
			$handler(nil, nil, [NSError errorWithDomain:kPortoErrorDomain code:2 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[location lastPathComponent], @"BadPortal", nil]]);
		}
	}
	else $handler(nil, nil, [NSError errorWithDomain:kPortoErrorDomain code:-1 userInfo:nil]);
	
	[connection cancel];
	[self endConnection];

	return nil;
}

- (void)authenticateWithHandler:(SessionAuthenticationHandler)handler {
	$handler = [handler copy];

	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:kPortoLoginURL]];
	[request setHTTPMethod:@"POST"];
	[request setHTTPShouldHandleCookies:NO];
	
	NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:
		$username, kPortoLoginUsernameKey,
		$password, kPortoLoginPasswordKey,
		nil];
	[request setHTTPBody:[[data urlEncodedString] dataUsingEncoding:NSUTF8StringEncoding]];
	
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
	$connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
	[request release];
}

- (void)dealloc {
	[$username release];
	[$password release];
	[super dealloc];
}
@end

/* }}} */

/* Session Controller {{{ */

@implementation SessionController
+ (SessionController *)sharedInstance {
	static SessionController *sessionController = nil;

	static dispatch_once_t token;
	dispatch_once(&token, ^{
		sessionController = [[[self class] alloc] init];
	});

	return sessionController;
}

- (id)init {
	if ((self = [super init])) {
		$keychainItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoApp" accessGroup:@"am.theiostre.portoapp.keychain"];
		$gradeKeyItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppX" accessGroup:@"am.theiostre.portoapp.keychain"];
		$papersKeyItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppY" accessGroup:@"am.theiostre.portoapp.keychain"];

		if (![[$keychainItem objectForKey:(id)kSecAttrAccount] isEqualToString:@""]) {
			$accountInfo = [[NSDictionary dictionaryWithObjectsAndKeys:
				[$keychainItem objectForKey:(id)kSecAttrAccount], kPortoUsernameKey,
				[$keychainItem objectForKey:(id)kSecValueData], kPortoPasswordKey,
				nil] retain];
		}
		else $accountInfo = nil;

		if (![[$gradeKeyItem objectForKey:(id)kSecAttrAccount] isEqualToString:@""]){
			$gradeID = [[$gradeKeyItem objectForKey:(id)kSecValueData] retain];
		}
		else $gradeID = nil;
		
		if (![[$papersKeyItem objectForKey:(id)kSecAttrAccount] isEqualToString:@""]){
			$papersID = [[$papersKeyItem objectForKey:(id)kSecValueData] retain];
		}
		else $papersID = nil;

		$sessionInfo = nil;
	}

	return self;
}

- (NSDictionary *)accountInfo {
	return $accountInfo;
}

- (void)setAccountInfo:(NSDictionary *)accountInfo {
	if ($accountInfo != nil) [$accountInfo release];
	
	if (accountInfo == nil) {
		[$keychainItem resetKeychainItem];
	}
	else {
		[$keychainItem setObject:[accountInfo objectForKey:kPortoUsernameKey] forKey:(id)kSecAttrAccount];
		[$keychainItem setObject:[accountInfo objectForKey:kPortoPasswordKey] forKey:(id)kSecValueData];
	}

	$accountInfo = [accountInfo retain];
}

- (BOOL)hasAccount {
	return $accountInfo != nil;
}

- (NSString *)gradeID {
	return $gradeID;
}

- (void)setGradeID:(NSString *)gradeID {
	if ($gradeID != nil) [$gradeID release];
	
	if (gradeID == nil) [$gradeKeyItem resetKeychainItem];
	else {
		// FIXME: There must be a better keychain class or whatever for this purpose.
		[$gradeKeyItem setObject:@"bacon" forKey:(id)kSecAttrAccount];
		[$gradeKeyItem setObject:gradeID forKey:(id)kSecValueData];
		NSLog(@"NEW GRADE KEY ITEM %@", [$gradeKeyItem objectForKey:(id)kSecValueData]);
	}

	$gradeID = [gradeID retain];
}

- (NSString *)papersID {
	return $papersID;
}

- (void)setPapersID:(NSString *)papersID {
	if ($papersID != nil) [$papersID release];

	if (papersID == nil) [$papersKeyItem resetKeychainItem];
	else {
		// FIXME: Same as above.
		[$papersKeyItem setObject:@"b4c0n" forKey:(id)kSecAttrAccount];
		[$papersKeyItem setObject:papersID forKey:(id)kSecValueData];
	}

	$papersID = [papersID retain];
}

- (NSDictionary *)sessionInfo {
	return $sessionInfo;
}

- (void)setSessionInfo:(NSDictionary *)sessionInfo {
	if ($sessionInfo != nil) [$sessionInfo release];
	$sessionInfo = [sessionInfo retain];
}

- (BOOL)hasSession {
	return $sessionInfo != nil;
}

- (void)loadSessionWithHandler:(void(^)(BOOL, NSError *))handler {
	NSLog(@"$accountInfo = %@", $accountInfo);
	if ($accountInfo == nil) {
		handler(NO, [NSError errorWithDomain:kPortoErrorDomain code:10 userInfo:nil]);
		return;
	}
	
	SessionAuthenticator *authenticator = [[SessionAuthenticator alloc] initWithUsername:[$accountInfo objectForKey:kPortoUsernameKey] password:[$accountInfo objectForKey:kPortoPasswordKey]];
	
	[authenticator authenticateWithHandler:^(NSArray *cookies, NSString *portal, NSError *error){
		NSLog(@"AUTHENTICATOR PORTAL %@", portal);

		if (portal != nil) {
			NSString *nameCookie;
			NSString *gradeCookie;
			NSString *genderCookie;
			
			NSString *sessionCookie;
			NSString *sessionCookieName;
			NSString *serverIdCookie;
			NSString *sessionIdCookie;

			for (NSHTTPCookie *cookie in cookies) {
				NSString *name = [cookie name];
				if ([name isEqualToString:kPortoGenderCookie]) genderCookie = [cookie value];
				else if ([name isEqualToString:kPortoGradeCookie]) gradeCookie = [cookie value];
				else if ([name isEqualToString:kPortoNameCookie]) nameCookie = [cookie value];
				else if ([name isEqualToString:kPortoServerIdCookie]) serverIdCookie = [cookie value];
				else if ([name isEqualToString:kPortoSessionIdCookie]) sessionIdCookie = [cookie value];
				else if ([name hasPrefix:kPortoASPSessionCookie]) {
					sessionCookieName = name;
					sessionCookie = [cookie value];
				}
			}
			
			NSDictionary *sessionInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				portal, kPortoPortalKey,
				sessionCookieName, kPortoCookieNameKey,
				sessionCookie, kPortoCookieKey,
				nameCookie, kPortoNameKey,
				gradeCookie, kPortoGradeKey,
				genderCookie, kPortoGenderKey,
				sessionIdCookie, kPortoSessionIdKey,
				serverIdCookie, kPortoServerIdKey,
				nil];
			[self setSessionInfo:sessionInfo];

			handler(YES, nil);
		}
		else handler(NO, error);
	}];
	[authenticator release];
}

- (NSData *)loadPageWithURL:(NSURL *)url method:(NSString *)method response:(NSURLResponse **)response error:(NSError **)error {
	NSHTTPCookie *aspCookie = [NSHTTPCookie cookieWithProperties:[NSDictionary dictionaryWithObjectsAndKeys:
		@"www.educacional.com.br", NSHTTPCookieDomain,
		@"/", NSHTTPCookiePath,
		[[self sessionInfo] objectForKey:kPortoCookieNameKey], NSHTTPCookieName,
		[[self sessionInfo] objectForKey:kPortoCookieKey], NSHTTPCookieValue,
		nil]]; //lol
	NSHTTPCookie *serverCookie = [NSHTTPCookie cookieWithProperties:[NSDictionary dictionaryWithObjectsAndKeys:
		@"www.educacional.com.br", NSHTTPCookieDomain,
		@"/", NSHTTPCookiePath,
		kPortoServerIdCookie, NSHTTPCookieName,
		[[self sessionInfo] objectForKey:kPortoServerIdKey], NSHTTPCookieValue,
		nil]];
	NSHTTPCookie *sessionCookie = [NSHTTPCookie cookieWithProperties:[NSDictionary dictionaryWithObjectsAndKeys:
		@"www.educacional.com.br", NSHTTPCookieDomain,
		@"/", NSHTTPCookiePath,
		kPortoSessionIdCookie, NSHTTPCookieName,
		[[self sessionInfo] objectForKey:kPortoSessionIdKey], NSHTTPCookieValue,
		nil]];

	NSDictionary *headers = [NSHTTPCookie requestHeaderFieldsWithCookies:[NSArray arrayWithObjects:aspCookie, serverCookie, sessionCookie, nil]];
	NSLog(@"HEADERS %@", headers);

	NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
	[urlRequest setAllHTTPHeaderFields:headers];
	[urlRequest setHTTPMethod:method];
	
	if ([method isEqualToString:@"POST"]) {
		NSString *urlString = [url absoluteString];
		NSArray *parts = [urlString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"?"]];
		NSLog(@"parts are %@ %@", [parts objectAtIndex:0], [parts objectAtIndex:1]);
		[urlRequest setURL:[NSURL URLWithString:[parts objectAtIndex:0]]];
		[urlRequest setHTTPBody:[[parts objectAtIndex:1] dataUsingEncoding:NSUTF8StringEncoding]];
	}
	
	return [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:response error:error];
}

- (void)dealloc {
	[$keychainItem release];
	[$accountInfo release];
	[$sessionInfo release];
	
	[super dealloc];
}
@end

/* }}} */

/* }}} */

/* Web View Controller {{{ */

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation WebViewController
@dynamic delegate, scrollView, request, canGoBack, canGoForward, loading, scalesPageToFit, detectsPhoneNumbers, dataDetectorTypes, allowsInlineMediaPlayback, mediaPlaybackRequiresUserAction, mediaPlaybackAllowsAirPlay, suppressesIncrementalRendering, keyboardDisplayRequiresUserAction, paginationMode, paginationBreakingMode, pageLength, gapBetweenPages, pageCount;

// Thanks Conrad.
- (BOOL)shouldForwardSelector:(SEL)aSelector {
	return (![[[self webView] superclass] instancesRespondToSelector:aSelector] && [[self webView] respondsToSelector:aSelector]);
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
	return (![self respondsToSelector:aSelector] && [self shouldForwardSelector:aSelector]) ? [self webView] : self;
}

- (void)loadView {
	UIWebView *webView = [[UIWebView alloc] initWithFrame:CGRectZero];
	[webView setScalesPageToFit:YES];
	[webView setDelegate:self];
	[self setView:webView];
	[webView release];
}

- (void)viewDidLoad {
        [super viewDidLoad];
        if (SYSTEM_VERSION_GT_EQ(@"7.0"))
                [self setAutomaticallyAdjustsScrollViewInsets:NO];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[UIView animateWithDuration:.1f animations:^{
                [[self webView] setFrame:PerfectFrameForViewController(self)];
        }];
}

- (void)loadURL:(NSURL *)pageURL {
	NSURLRequest *request = [[NSURLRequest alloc] initWithURL:pageURL];
	[self loadRequest:request];
	[request release];
}

- (void)loadPage:(NSString *)page {
	[self loadURL:[NSURL URLWithString:page]];
}

- (void)loadLocalFile:(NSString *)path {
	[self loadURL:[NSURL fileURLWithPath:path]];
}

- (NSString *)executeJavascript:(NSString *)javascript {
	return [[self webView] stringByEvaluatingJavaScriptFromString:javascript];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
	[[[self webView] scrollView] setContentOffset:CGPointMake(0, 0)];
}

- (UIWebView *)webView {
	return (UIWebView *)[self view];
}
@end

#pragma clang diagnostic pop

/* }}} */

/* Web Data Controller {{{ */

// The whole -loadContentView API is not need-based. Rather, it is called on the controller's -loadView,
// and -unload is called on memory issues.
// That is, this is just a custom way to initialize and manipulate our main view, not really an
// awesome system to handle content views on-demand.
// Thought, might it be a good idea to implement this? We'd be splitting a view's management from
// our view controller's, but is that a bad thing if it spares us memory?

@implementation WebDataViewController
- (id)init {
	NSLog(@"Calling -[WebDataViewController init], and using default identifier. THIS MAY CAUSE ERRORS.");
	return [self initWithIdentifier:@"default"];
}

- (id)initWithIdentifier:(NSString *)identifier_ {
	if ((self = [super init])) {
		char *identifier;
		asprintf(&identifier, "am.theiostre.portoapp.webdata.%s", [identifier_ UTF8String]);
		
		$queue = dispatch_queue_create(identifier, NULL);
		dispatch_retain($queue);
	}

	return self;
}

- (void)loadView {
	[super loadView];

	$loadingView = [[LoadingIndicatorView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[[self view] addSubview:$loadingView];

	$failureView = [[FailView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[$failureView setBackgroundColor:[UIColor redColor]];
	[$failureView setHidden:YES];
	[[self view] addSubview:$failureView];
	
	$contentView = nil;
	[self loadContentView];
	[$contentView setHidden:YES];
	[[self view] addSubview:$contentView];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	if ([[self view] window] == nil) {
		[self freeData];
		
		if (SYSTEM_VERSION_GT_EQ(@"6.0")) {
			[self $freeViews];
			[self setView:nil];
		}
	}
}

- (void)viewDidUnload {
	[super viewDidUnload];
	if (!SYSTEM_VERSION_GT_EQ(@"6.0")) [self $freeViews];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self refresh];

	// TODO: Add a session id check here (would be convenient)
}

- (void)refresh {
	[self $performUIBlock:^{ [self displayLoadingView]; }];
	if ([NSThread isMainThread]) dispatch_async($queue, ^{ [self reloadData]; });
	else [self reloadData];
}

- (void)reloadData {
	return;
}

- (Class)contentViewClass {
	return [UIView class];
}

- (UIView *)contentView {
	return $contentView;
}

- (void)freeData {
	return;
}

- (void)$performUIBlock:(void(^)())block {
	if ([NSThread isMainThread]) block();
	else dispatch_sync(dispatch_get_main_queue(), block);
}

- (void)displayLoadingView {
	[self $performUIBlock:^{
		[$failureView setHidden:YES];
		[self hideContentView];

		[[$loadingView activityIndicatorView] startAnimating];
		[$loadingView setHidden:NO];
	}];
}

- (void)hideLoadingView {
	[self $performUIBlock:^{
		[$loadingView setHidden:YES];
		[[$loadingView activityIndicatorView] stopAnimating];
	}];
}

- (void)hideContentView {
	[self $performUIBlock:^{
		[$contentView setHidden:YES];
	}];
}

- (void)displayFailViewWithImage:(UIImage *)image text:(NSString *)text {
	[self $performUIBlock:^{
		[self hideLoadingView];
		[self hideContentView];
		
		[$failureView setImage:image];
		[$failureView setText:text];
		[$failureView setNeedsLayout];
		[$failureView setHidden:NO];
	}];
}

- (void)displayContentView {
	[self $performUIBlock:^{
		[self hideLoadingView];
		[$failureView setHidden:YES];

		NSLog(@"we just set $contentView.hidden to NO!");
		[$contentView setHidden:NO];
		NSLog(@"eh? %d", [$contentView isHidden]);
	}];
}

- (void)displayErrorAlertViewWithTitle:(NSString *)title message:(NSString *)message {
	[self $performUIBlock:^{
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"Descartar" otherButtonTitles:nil];
		[alertView show];
		[alertView release];
	}];
}

- (void)loadContentView {
	$contentView = [[UIView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
}

- (void)unloadContentView {
	return;
}

- (void)$freeViews {
	[$loadingView release];
	[$failureView release];
	
	[self unloadContentView];
	[$contentView release];
}

- (void)dealloc {
	[self $freeViews];
	[self freeData];
	
	dispatch_release($queue);

	[super dealloc];
}
@end

/* }}} */

/* Login Controller {{{ */

/* Login UI Backbone {{{ */
@implementation LoginController
@synthesize delegate = $delegate;

- (void)$freeResourcesWithNil:(BOOL)nilify {
	[$tableView release];
	[$usernameCell release];
	[$passwordCell release];
	[$loadingCell release];
	[$topImageView release];
	[$bottomLabel release];
	[$cancelItem release];
	[$completeItem release];
	[$backgroundImageView release];
	[$tableContainerView release];
	[$centeringAlignmentView release];
	
	if (nilify) {
		$tableView = nil;
		$usernameCell = nil;
		$passwordCell = nil;
		$loadingCell = nil;
		$topImageView = nil;
		$bottomLabel = nil;
		$cancelItem = nil;
		$completeItem = nil;
		$tableContainerView = nil;
		$centeringAlignmentView = nil;
	}
    
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (UITextField *)$getTextField {
	UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
	[field setAdjustsFontSizeToFitWidth:YES];
	[field setTextColor:[UIColor blackColor]];
	[field setDelegate:self];
	[field setBackgroundColor:[UIColor clearColor]];
	[field setAutocorrectionType:UITextAutocorrectionTypeNo];
	[field setAutocapitalizationType:UITextAutocapitalizationTypeNone];
	[field setTextAlignment:NSTextAlignmentLeft];
	[field setEnabled:YES];
    
	return [field autorelease];
}

- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor blueColor]];
	
	$backgroundImageView = [[UIImageView alloc] initWithFrame:[[self view] bounds]];
	[[self view] addSubview:$backgroundImageView];

	CGRect centeringAlignmentFrame = CGRectMake(0, 0, [[self view] bounds].size.width, [[self view] bounds].size.height - 80.0f);
	$centeringAlignmentView = [[UIView alloc] initWithFrame:centeringAlignmentFrame];
	[[self view] addSubview:$centeringAlignmentView];
    
	$tableContainerView = [[UIView alloc] initWithFrame:[$centeringAlignmentView bounds]];
	[$centeringAlignmentView addSubview:$tableContainerView];
    
	$tableView = [[[UITableView alloc] initWithFrame:[$tableContainerView bounds] style:UITableViewStyleGrouped] autorelease];
	[$tableView setBackgroundColor:[UIColor clearColor]];
    	[$tableView setBackgroundView:[[[UIView alloc] init] autorelease]];
	[$tableView setDelegate:self];
	[$tableView setDataSource:self];
	[$tableView setScrollEnabled:NO];
	[$tableView setAllowsSelection:NO];
	[$tableContainerView addSubview:$tableView];
	
	CGRect fieldRect = CGRectMake(115, 12, -135, 30);
    
	$usernameCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[[$usernameCell textLabel] setText:@"Usuário"];
	$usernameField = [self $getTextField];
	[$usernameField setFrame:CGRectMake(fieldRect.origin.x, fieldRect.origin.y, $usernameCell.bounds.size.width + fieldRect.size.width, fieldRect.size.height)];
	[$usernameField setReturnKeyType:UIReturnKeyNext];
	[$usernameCell addSubview:$usernameField];
    
	$passwordCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[[$passwordCell textLabel] setText:@"Senha"];
	$passwordField = [self $getTextField];
	[$passwordField setFrame:CGRectMake(fieldRect.origin.x, fieldRect.origin.y, $passwordCell.bounds.size.width + fieldRect.size.width, fieldRect.size.height)];
	[$passwordField setSecureTextEntry:YES];
	[$passwordField setReturnKeyType:UIReturnKeyDone];
	[$passwordCell addSubview:$passwordField];
	
	$loadingCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	LoadingIndicatorView *loadingIndicatorView = [[LoadingIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 200, 50)];
	[loadingIndicatorView setCenter:[$loadingCell center]];
	[$loadingCell addSubview:loadingIndicatorView];
	
	$topImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0.f, 0.f, [$tableView bounds].size.width, 40.f)];
    
	$bottomLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [$tableView bounds].size.width, 15.f)];
	[$bottomLabel setTextAlignment:NSTextAlignmentCenter];
	[$bottomLabel setBackgroundColor:[UIColor clearColor]];
	[$bottomLabel setFont:[UIFont systemFontOfSize:14.f]];
    
	[$tableView layoutIfNeeded];
	
	CGFloat tableViewHeight = [$tableView contentSize].height;
	[$tableView setFrame:CGRectMake(0, floorf(($tableContainerView.bounds.size.height - tableViewHeight) / 2), $tableContainerView.bounds.size.width, tableViewHeight)];
	
	$completeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(sendRequest)];
	$cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	UIGraphicsBeginImageContext([[self view] bounds].size);
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();

	CGGradientRef gradient = CGGradientCreateWithColors(rgb, (CFArrayRef) [self gradientColors], NULL);
	CGFloat centerX = CGRectGetMidX([[self view] bounds]);
	CGFloat centerY = 110.f;
	CGPoint center = CGPointMake(centerX, centerY);
	CGContextDrawRadialGradient(context, gradient, center, 5.0f, center, 1500.0f, kCGGradientDrawsBeforeStartLocation);

	CGGradientRelease(gradient);
	CGColorSpaceRelease(rgb);

	UIImage *background = UIGraphicsGetImageFromCurrentImageContext();
	[$backgroundImageView setImage:background];

	UIGraphicsEndImageContext();
}

- (void)viewDidLoad {
	[super viewDidLoad];
    
	[[self navigationItem] setRightBarButtonItem:$completeItem];
	[[self navigationItem] setLeftBarButtonItem:$cancelItem];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateForKeyboardNotification:) name:UIKeyboardWillHideNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateForKeyboardNotification:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateForKeyboardNotification:) name:UIKeyboardWillChangeFrameNotification object:nil];
    
	[self setTitle:@"Login"];
}

- (void)viewDidUnload {
	[super viewDidUnload];
	[self $freeResourcesWithNil:YES];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[$usernameField becomeFirstResponder];
}

- (void)sendRequest {
	[[UIApplication sharedApplication] beginIgnoringInteractionEvents];
	
	$isAuthenticating = YES;
	[$tableView reloadData];

	[self authenticate];
}

- (void)endRequestWithSuccess:(BOOL)success error:(NSError *)error {
	$isAuthenticating = NO;
	[[UIApplication sharedApplication] endIgnoringInteractionEvents];

	if (success) [$delegate loginControllerDidLogin:self];
	else {
		UIAlertView *alert = [[UIAlertView alloc] init];
		[alert setTitle:@"Falha de login"];
		
		if ([error code] == 1)
			[alert setMessage:@"Foi impossível fazer login com estas credenciais. Verifique login e senha."];
		else if ([error code] == 2)
			[alert setMessage:[NSString stringWithFormat:@"O portal %@ não é suportado pelo app.", [[error userInfo] objectForKey:@"BadPortal"]]];
		else
			[alert setMessage:@"Erro desconhecido."];

		[alert addButtonWithTitle:@"Descartar"];
		[alert setCancelButtonIndex:0];
		[alert show];
		[alert release];

		[$tableView reloadData];
		[$passwordField becomeFirstResponder];
	}
}

- (void)authenticate {
	return;
}

- (void)cancel {
	[$delegate loginControllerDidCancel:self];
}

- (NSArray *)gradientColors {
	return nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	if (textField == $usernameField) [$passwordField becomeFirstResponder];
	else if (textField == $passwordField) [self sendRequest];
    
	return YES;
}

/*- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
 // update done
 }*/

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) {
        return $isAuthenticating ? 1 : 2;
    }
    
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return $isAuthenticating ? 88.f : 44.f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSLog(@"ROW %i AUTH %d", [indexPath row], $isAuthenticating);
    
    if ([indexPath row] == 0) return $isAuthenticating ? $loadingCell : $usernameCell;
	else if ([indexPath row] == 1) return $passwordCell;
    
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section == 0) return 65.f;
	return 0.f;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section == 0) return $topImageView;
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	if (section == 0) return 42.f;
	return 0.f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (section == 0) return $bottomLabel;
	return nil;
}

- (void)updateForKeyboardNotification:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    NSTimeInterval duration = [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    CGRect endingFrame = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect windowEndingFrame = [[$centeringAlignmentView window] convertRect:endingFrame fromWindow:nil];
    CGRect viewEndingFrame = [$centeringAlignmentView convertRect:windowEndingFrame fromView:nil];
    
    CGRect viewFrame = [$centeringAlignmentView bounds];
    CGRect endingIntersectionRect = CGRectIntersection(viewFrame, viewEndingFrame);
    viewFrame.size.height -= endingIntersectionRect.size.height;
    
    [UIView animateWithDuration:duration delay:0 options:(curve << 16) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [$tableContainerView setFrame:viewFrame];
        
        CGFloat tableViewHeight = [$tableView contentSize].height;
        [$tableView setFrame:CGRectMake(0, floorf(($tableContainerView.bounds.size.height - tableViewHeight) / 2), $tableContainerView.bounds.size.width, tableViewHeight)];
    } completion:NULL];
}

- (void)dealloc {
	[self $freeResourcesWithNil:NO];
	[super dealloc];
}
@end
/* }}} */

/* Login Controller / Authentication UI {{{ */
@implementation PortoLoginController
- (void)viewDidLoad {
	[super viewDidLoad];

	[$bottomLabel setText:@"Seus dados serão mandados apenas ao Porto."];
	[$bottomLabel setTextColor:[UIColor whiteColor]];
}

- (NSArray *)gradientColors {
	return [NSArray arrayWithObjects:
		(id)[UIColorFromHexWithAlpha(0x165EC4, 1.f) CGColor],
		(id)[UIColorFromHexWithAlpha(0x5781DE, 1.f) CGColor],
		nil];
}

- (void)authenticate {
	NSString *user = [$usernameField text];
	NSString *password = [$passwordField text];
	
	SessionController *controller = [SessionController sharedInstance];
	
	NSDictionary *previousAccountInfo = [controller accountInfo];
	[controller setAccountInfo:[NSDictionary dictionaryWithObjectsAndKeys:
		user, kPortoUsernameKey,
		password, kPortoPasswordKey,
		nil]];
	
	[controller loadSessionWithHandler:^(BOOL success, NSError *error){
		if (!success) [controller setAccountInfo:previousAccountInfo];
		else {
			[self generateGradeID];
			[self generatePapersID];
		}

		[self endRequestWithSuccess:success error:error];
	}];
}

// TODO: Is it a better approach to keep this here or in SessionController?
- (void)generateGradeID {
	SessionController *controller = [SessionController sharedInstance];
	NSURL *url = [NSURL URLWithString:[@"http://www.educacional.com.br/" stringByAppendingString:[[controller sessionInfo] objectForKey:kPortoPortalKey]]];

	NSURLResponse *response;
	NSError *error;
	NSData *portalData = [controller loadPageWithURL:url method:@"GET" response:&response error:&error];
	if (portalData == nil) {
		[controller setGradeID:nil];
		return;
	}
	
	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:portalData];
	XMLElement *boletimHref = [document firstElementMatchingPath:@"/html/body/div[@id='educ_geralexterno']/div[@id='educ_bgcorpo']/div[@id='educ_corpo']/div[@id='educ_conteudo']/div[@class='A']/div[@class='A_meio_bl']/div[@class='A_panel_bl  A_panel_hidden_bl ']/div[@class='botoes']/a[1]"];
	NSString *function = [[boletimHref attributes] objectForKey:@"href"];
	
	if (function == nil) {
		[document release];
		[controller setGradeID:nil];
		return;
	}

	NSRange parRange = [function rangeOfString:@"fPS_Boletim"];
	NSString *parameter = [function substringFromIndex:parRange.location + parRange.length];
	NSString *truyyut = [parameter substringWithRange:NSMakeRange(2, [parameter length]-5)];
	[document release];
	
	url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.educacional.com.br/barra_logados/servicos/portoseguro_notasparciais.asp?x=%@", truyyut]];
	NSData *data = [controller loadPageWithURL:url method:@"GET" response:&response error:&error];
	if (data == nil) {
		[controller setGradeID:nil];
		return;
	}

	document = [[XMLDocument alloc] initWithHTMLData:data];
	XMLElement *medElement = [document firstElementMatchingPath:@"/html/body/form/input"];
	if (medElement == nil) {
		[document release];
		[controller setGradeID:nil];
		return;
	}

	NSString *token = [[medElement attributes] objectForKey:@"value"];
	[document release];

	[controller setGradeID:token];
}

/* 
Funnily, they have this fun security issue where if you go to iframe_comunicados.asp without any cookies
you will still get a valid token for name "Funcionário".
*/

- (void)generatePapersID {
	SessionController *controller = [SessionController sharedInstance];
	//NSURL *papersURL = [NSURL URLWithString:@"http://www.educacional.com.br/rd/gravar.asp?servidor=http://portoseguro.educacional.net&url=/educacional/comunicados.asp"];
	NSURL *papersURL = [NSURL URLWithString:@"http://portoseguro.educacional.net/educacional/iframe_comunicados.asp"];

	NSURLResponse *response;
	NSError *error;
	NSData *papersPageData = [controller loadPageWithURL:papersURL method:@"GET" response:&response error:&error];
	if (papersPageData == nil) {
		[controller setPapersID:nil];
		return;
	}
	
	// Since libxml doesn't like this page, we'll need to do parsing ourselves.
	// I think this deserves an URGENT FIXME.
	const char *pageData = (const char *)[papersPageData bytes];
	char *input = strstr(pageData, "<input");
	char *close = strstr(input, ">");
	char *value = strstr(input, "value");
	if (close <= value) {
		[controller setPapersID:nil];
		return;
	}

	value += 7; //strlen("value=\"")
	char *c = value;;
	while (*c != '"') c++;
	*c = '\0';
	
	NSLog(@"value is %s", value);
	[controller setPapersID:[NSString stringWithUTF8String:value]];
}
@end
/* }}} */

/* }}} */

/* News Controller {{{ */

@implementation NewsIndexViewController
@end

@implementation NewsItemView

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		sectionSize = CGSizeZero;
		titleSize = CGSizeZero;
		subtitleSize = CGSizeZero;
		
		bodyFramesettersCount = 0;
		imagesCount = 0;

		textColor = (CGColorRef)CFRetain([[UIColor blackColor] CGColor]);
		
		NSString *systemFont = [[UIFont systemFontOfSize:1.f] fontName];
		bodyFont = CTFontCreateWithName((CFStringRef)systemFont, 15.f, NULL);
		sectionFont = CTFontCreateWithName((CFStringRef)systemFont, 24.f, NULL);
		titleFont = CTFontCreateCopyWithSymbolicTraits(bodyFont, 32.f, NULL, kCTFontBoldTrait, kCTFontBoldTrait);
		subtitleFont = CTFontCreateCopyWithSymbolicTraits(bodyFont, 15.f, NULL, kCTFontItalicTrait, kCTFontItalicTrait);
		
		sectionFramesetter = NULL;
		titleFramesetter = NULL;
		subtitleFramesetter = NULL;
		
		bodyFramesetters = NULL;
		bodySizes = nil;
		contents = nil;
	}

	return self;
}

- (void)setSection:(NSString *)section {
	if (sectionFramesetter != NULL) CFRelease(sectionFramesetter);
	sectionFramesetter = CreateFramesetter(sectionFont, textColor, (CFStringRef)section, YES);
}

- (void)setTitle:(NSString *)title {
	if (titleFramesetter != NULL) CFRelease(titleFramesetter);
	titleFramesetter = CreateFramesetter(titleFont, textColor, (CFStringRef)title, NO);
}

- (void)setSubtitle:(NSString *)subtitle {
	if (subtitleFramesetter != NULL) CFRelease(subtitleFramesetter);
	subtitleFramesetter = CreateFramesetter(subtitleFont, textColor, (CFStringRef)[subtitle stringByReplacingOccurrencesOfString:@"\t" withString:@""], NO);
}

- (void)setContents:(NSArray *)contents_ {
	if (bodyFramesetters != NULL) free(bodyFramesetters);
	if (contents != nil) [contents release];
	contents = [contents_ retain];

	bodyFramesetters = (CTFramesetterRef *)calloc([contents count], sizeof(CTFramesetterRef));
	bzero(bodyFramesetters, [contents count]);
	
	for (id content in contents) {
		if ([content isKindOfClass:[NSString class]]) {
			CTFramesetterRef framesetter = CreateFramesetter(bodyFont, textColor, (CFStringRef)content, NO);
			bodyFramesetters[bodyFramesettersCount++] = framesetter;
		}
		else if ([content isKindOfClass:[UIImage class]]) imagesCount++;
	}
}

- (CGFloat)heightOffset {
	//return bodyFramesettersCount * CTFontGetSize(bodyFont)*96/72 + CTFontGetSize(subtitleFont)*96/72;
	return 6 * pttopx(CTFontGetSize(bodyFont)); // don't ask me why. Just don't. I don't know.
}

- (CGSize)sizeThatFits:(CGSize)size {
	if (bodySizes != nil) [bodySizes release];
	bodySizes = [[NSMutableArray alloc] init];
	
	CGFloat ret = 0.f;
	CGFloat width = size.width;
	
	titleSize = CTFramesetterSuggestFrameSizeWithConstraints(titleFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(width-10.f, CGFLOAT_MAX), NULL);
	subtitleSize = CTFramesetterSuggestFrameSizeWithConstraints(subtitleFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(width-10.f, CGFLOAT_MAX), NULL);
	sectionSize = CTFramesetterSuggestFrameSizeWithConstraints(sectionFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(width-10.f, CGFLOAT_MAX), NULL);
	ret += titleSize.height + subtitleSize.height + sectionSize.height/* + 3 * 5.f*/;
	NSLog(@"ret += %f = %f", titleSize.height + subtitleSize.height + sectionSize.height, ret);
	
	NSUInteger framesetters = 0;
	for (id content in contents) {
		if ([content isKindOfClass:[NSString class]]) {
			CTFramesetterRef framesetter = bodyFramesetters[framesetters];
			CGSize bodySize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(width-10.f, CGFLOAT_MAX), NULL);
			[bodySizes addObject:NSStringFromCGSize(bodySize)];

			ret += bodySize.height /*+ 5.f*/;
			NSLog(@"ret += %f = %f", bodySize.height, ret);
			framesetters++;
		}

		else if ([content isKindOfClass:[UIImage class]]) {
			UIImage *image = (UIImage *)content;
			CGSize imageSize = [image size];

			CGFloat ratio = width / imageSize.width;
			CGFloat height = ratio * imageSize.height;
			ret += height;
			NSLog(@"ret += %f = %f", height, ret);
		}
	}
	
	return CGSizeMake(width, ret + imagesCount * 7.f);
}

- (void)drawRect:(CGRect)rect {
	NSLog(@"DRAW RECT: %@", NSStringFromCGRect(rect));

	CGContextRef context = UIGraphicsGetCurrentContext();
	[[UIColor whiteColor] setFill];
	CGContextFillRect(context, rect);
	
	CGContextSetTextPosition(context, 0.f, 0.f);
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextTranslateCTM(context, 0, [self bounds].size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	
	NSUInteger bodyProgression = bodyFramesettersCount;
	CGFloat startY = 0.f;
	for (int i = [contents count]-1; i>=0; i--) {
		if ([[contents objectAtIndex:i] isKindOfClass:[NSString class]]) {
			CTFramesetterRef framesetter = bodyFramesetters[--bodyProgression];
			
			CGRect bodyRect = CGRectMake(7.f, startY, rect.size.width - 14.f, CGSizeFromString([bodySizes objectAtIndex:bodyProgression]).height);

			NSLog(@"BODY RECT: %@", NSStringFromCGRect(bodyRect));
			CTFrameRef bodyFrame = CreateFrame(framesetter, bodyRect);
			CTFrameDraw(bodyFrame, context);
			CFRelease(bodyFrame);

			startY += bodyRect.size.height;
		}

		else if ([[contents objectAtIndex:i] isKindOfClass:[UIImage class]]) {
			UIImage *image = (UIImage *)[contents objectAtIndex:i];
			CGSize imageSize = [image size];

			CGFloat ratio = rect.size.width / imageSize.width;
			CGFloat height = ratio * imageSize.height;
			
			CGImageRef img = [image CGImage];
			CGContextDrawImage(context, CGRectMake(0.f, startY - 7.f, rect.size.width, height), img);
			NSLog(@"IMAGE RECT: %@", NSStringFromCGRect(CGRectMake(0.f, startY, rect.size.width, height)));
			CFRelease(img);
			
			startY += height + 7.f;
		}
	}
	
	CGRect subtitleRect = CGRectMake(7.f, startY, rect.size.width - 14.f, subtitleSize.height);
	NSLog(@"SUBTITLE %@", NSStringFromCGRect(subtitleRect));
	startY += subtitleSize.height;
	CGRect titleRect = CGRectMake(7.f, startY, rect.size.width - 14.f, titleSize.height);
	NSLog(@"TITLE %@", NSStringFromCGRect(titleRect));
	startY += titleSize.height /*+ 5.f*/;
	CGRect sectionRect = CGRectMake(7.f, startY, rect.size.width - 14.f, sectionSize.height);
	NSLog(@"SECTION %@", NSStringFromCGRect(sectionRect));
	
	CTFrameRef sectionFrame = CreateFrame(sectionFramesetter, sectionRect);
	CTFrameRef titleFrame = CreateFrame(titleFramesetter, titleRect);
	CTFrameRef subtitleFrame = CreateFrame(subtitleFramesetter, subtitleRect);
	CTFrameDraw(sectionFrame, context);
	CTFrameDraw(titleFrame, context);
	CTFrameDraw(subtitleFrame, context);
	CFRelease(titleFrame);
	CFRelease(subtitleFrame);
	CFRelease(sectionFrame);
}

- (void)dealloc {
	CFRelease(textColor);
	CFRelease(sectionFont);
	CFRelease(titleFont);
	CFRelease(subtitleFont);
	CFRelease(bodyFont);
	CFRelease(sectionFramesetter);
	CFRelease(titleFramesetter);
	CFRelease(subtitleFramesetter);

	[contents release];
	for (int i=0; i<bodyFramesettersCount; i++) CFRelease(bodyFramesetters[i]);
	free(bodyFramesetters);
	[bodySizes release];

	[super dealloc];
}
@end

@implementation NewsItemViewController
- (id)initWithURL:(NSURL *)url {
	if ((self = [super init])) {
		$url = [url retain];

		$isLoading = YES;
	}

	return self;
}

- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor whiteColor]];

	$loadingView = [[LoadingIndicatorView alloc] initWithFrame:[[self view] bounds]];
	[[self view] addSubview:$loadingView];
	
	$scrollView = [[UIScrollView alloc] initWithFrame:[[self view] bounds]];
	[$scrollView setHidden:YES];
	[[self view] addSubview:$scrollView];
	
	$contentView = [[NewsItemView alloc] initWithFrame:CGRectMake(0.f, 0.f, [[self view] bounds].size.width, 0.f)];
	[$scrollView addSubview:$contentView];

	$webView = [[UIWebView alloc] initWithFrame:[[self view] bounds]];
	[$webView setHidden:YES];
	[$webView setDelegate:self];
	[[self view] addSubview:$webView];
	
	[[self view] addSubview:$scrollView];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Artigo"];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSData *data = [NSData dataWithContentsOfURL:$url];
		if (data == nil) {
			dispatch_sync(dispatch_get_main_queue(), ^{
				;
			});
			
			return;
		}

		XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
		NSLog(@"%@", document);

		XMLElement *content = [document firstElementMatchingPath:@"/html/body/div[@id = 'main']/section/div[starts-with(@id, 'content')]/div[starts-with(@class, 'conteudo')]"];
		if (content == nil) {
			[document release];
			
			dispatch_sync(dispatch_get_main_queue(), ^{
				[self failContentViewWithHTMLData:data];
			});

			return;
		}
		
		XMLElement *sectionElement = [content firstElementMatchingPath:@"./div[@class='titulo']/h2"];

		NSString *cls = [[content attributes] objectForKey:@"class"];
		XMLElement *articleElement = [cls hasSuffix:@"-2"] ? [content firstElementMatchingPath:@"./article"] : content;
		NSArray *paragraphs = [articleElement elementsMatchingPath:@"./p[not(contains(text(), 'javascript:')) and string-length(text())>0]"];

		XMLElement *titleElement = [articleElement firstElementMatchingPath:@"./h4"];
		XMLElement *subtitleElement = nil;
		
		BOOL hasImageElement = NO;
		NSUInteger paragraphCount = 0;
		for (XMLElement *element in paragraphs) {
			if ([element firstElementMatchingPath:@"./img"]) { hasImageElement = YES; break; }
			else if (subtitleElement == nil) subtitleElement = element;
			paragraphCount++;
		}
		if (!hasImageElement || paragraphCount > 1) {
			if (![subtitleElement firstElementMatchingPath:@"./em"]) //FIXME
				subtitleElement = nil;
		}
		
		NSString *section = sectionElement ? [sectionElement content] : nil;
		NSString *title = titleElement ? [titleElement content] : nil;
		NSString *subtitle = subtitleElement ? ParseNewsParagraph([subtitleElement content]) : nil;
		NSMutableArray *contents = [NSMutableArray array];

		NSUInteger startIndex = subtitle ? 1 : 0;
		for (NSUInteger i = startIndex; i < [paragraphs count]; i++) {
			XMLElement *imageElement = nil;
			if ((imageElement = [[paragraphs objectAtIndex:i] firstElementMatchingPath:@"./img"]))
				[contents addObject:[UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[kPortoRootURL stringByAppendingString:[[imageElement attributes] objectForKey:@"src"]]]]]];
			else {
				NSString *parsed = ParseNewsParagraph([[paragraphs objectAtIndex:i] content]);
				if ([parsed length] > 4) // That is \n, \t, \u00a0 and another mysterious char. (\0?)
					[contents addObject:parsed];
			}
		}

		dispatch_sync(dispatch_get_main_queue(), ^{
			[$contentView setSection:section];
			[$contentView setTitle:title];
			[$contentView setSubtitle:subtitle];
			[$contentView setContents:contents];

			[self enableContentView];
		});

		[document release];
	});
}

- (void)failContentViewWithHTMLData:(NSData *)data {
	[$webView loadData:data MIMEType:@"text/html" textEncodingName:@"utf-8" baseURL:$url];
	
	[self hideLoadingView];
	[$webView setHidden:NO];
}

- (void)hideLoadingView {
	[[$loadingView activityIndicatorView] stopAnimating];
	[$loadingView setHidden:YES];
}


- (void)enableContentView {
	[self hideLoadingView];
	
	[$contentView sizeToFit];
	[$contentView setNeedsDisplay];
	
	[$scrollView setContentSize:CGSizeMake([$contentView bounds].size.width, [$contentView bounds].size.height + [$contentView heightOffset])];
	NSLog(@"size %@ contentsize %@", NSStringFromCGRect([$contentView bounds]), NSStringFromCGSize([$scrollView contentSize]));
	[$scrollView setHidden:NO];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type {
	return NO;
}

- (void)dealloc {
	[$url release];

	[$loadingView release];
	[$scrollView release];
	[$contentView release];
	[$webView release];
	[super dealloc];
}
@end

@implementation NewsViewController
- (id)init {
	if ((self = [super init])) {
		$imageData = [[NSMutableArray alloc] init];
		$isLoading = YES;
	}

	return self;
}

- (void)loadView {
	$tableView = [[UITableView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame] style:UITableViewStylePlain];
	[$tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
	[$tableView setScrollEnabled:NO];
	[self setTableView:$tableView];

	$loadingCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	LoadingIndicatorView *loadingIndicatorView = [[[LoadingIndicatorView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
	[loadingIndicatorView setCenter:[$loadingCell center]];
	[loadingIndicatorView setTag:1];
	[$loadingCell addSubview:loadingIndicatorView];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	[self setTitle:@"Notícias"];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://www.portoseguro.org.br"]];
		
		XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
		NSArray *list = [document elementsMatchingPath:@"//body/div[@id = 'main']/div[@id = 'banner']/div[@id = 'bannerFoto']/ul/li"];
		
		for (XMLElement *banner in list) {
			XMLElement *span = [banner firstElementMatchingPath:@".//div/span"];
			XMLElement *a = [banner firstElementMatchingPath:@".//a"];
			
			XMLElement *title = [banner firstElementMatchingPath:@".//div/h2/a"];
			XMLElement *subtitle = [banner firstElementMatchingPath:@".//div/p/a"];

			XMLElement *img = [banner firstElementMatchingPath:@".//a/img"];
			UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[kPortoRootURL stringByAppendingString:[[img attributes] objectForKey:@"src"]]]]];

			NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
				[span content], @"Porto",
				[[a attributes] objectForKey:@"href"], @"Link",
				[title content], @"Title",
				[subtitle content], @"Subtitle",
				image, @"Image",
				nil];
			[$imageData addObject:result];
		}

		NSLog(@"ARRY %@", $imageData);
		
		NSDictionary *more = [NSDictionary dictionaryWithObjectsAndKeys:
			@"Arquivo", @"Porto",
			@"$AconteceNoPorto", @"Link",
			@"Acontece no Porto", @"Title",
			@"Veja aqui um catálogo de todas as notícias arquivadas.", @"Subtitle",
			[UIImage imageNamed:@"acontece_no_porto.gif"], @"Image",
			nil];
		[$imageData addObject:more];
		
		[document release];

		$isLoading = NO;
		dispatch_sync(dispatch_get_main_queue(), ^{
			[$tableView setScrollEnabled:YES];
			[$tableView reloadData];
		});
	});
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return $isLoading ? 1 : [$imageData count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return $isLoading ? 0.f : 30.f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ($isLoading) return [[self tableView] bounds].size.height;

	NSString *subtitle = [[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Subtitle"];
	CGSize subtitleSize = [subtitle sizeWithFont:[UIFont systemFontOfSize:16.f] constrainedToSize:CGSizeMake([tableView bounds].size.width - 6.f, CGFLOAT_MAX)];
	return 160.f + subtitleSize.height;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
	return !$isLoading;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ($isLoading) return $loadingCell;
	
	static NSString *cellIdentifier = @"PortoNewsCellIdentifier";
	NewsTableViewCell *cell = (NewsTableViewCell *)[tableView dequeueReusableCellWithIdentifier:cellIdentifier];
	if (cell == nil) {
		cell = [[[NewsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
	}
	
	[cell setNewsImage:[[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Image"]];
	[cell setNewsTitle:[[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Title"]];
	[cell setNewsSubtitle:[[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Subtitle"]];
	[cell setNeedsDisplay];

	return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if ($isLoading) return nil;
	
	NSString *text = [[$imageData objectAtIndex:section] objectForKey:@"Porto"];
	if ([text isEqualToString:@""]) text = @"Institucional";

	UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, [tableView bounds].size.width, 30.f)] autorelease];
	[view setBackgroundColor:UIColorFromHexWithAlpha(/*0x34333D*/0x203259, 1.f)];
	
	UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(5.f, 3.f, [tableView bounds].size.width - 12.f, 24.f)] autorelease];
	[label setBackgroundColor:[UIColor clearColor]];
	[label setTextColor:[UIColor whiteColor]];
	[label setFont:[UIFont systemFontOfSize:19.f]];
	[label setText:text];
	[view addSubview:label];

	return view;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if ($isLoading) return;
	
	NSString *link = [[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Link"];
	if ([link isEqualToString:@"$AconteceNoPorto"]) {
		NewsIndexViewController *indexViewController = [[[NewsIndexViewController alloc] init] autorelease];
		[[self navigationController] pushViewController:indexViewController animated:YES];
	}
	else {
		NewsItemViewController *itemViewController = [[[NewsItemViewController alloc] initWithURL:[NSURL URLWithString:link]] autorelease];
		[[self navigationController] pushViewController:itemViewController animated:YES];
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)dealloc {
	[$tableView release];
	[$loadingCell release];
	[$imageData release];

	[super dealloc];
}
@end

@implementation NewsTableViewCell
@synthesize newsImage = $newsImage, newsTitle = $newsTitle, newsSubtitle = $newsSubtitle;

- (void)drawContentView:(CGRect)rect highlighted:(BOOL)highlighted {
	CGContextRef context = UIGraphicsGetCurrentContext();

	[[UIColor whiteColor] setFill];
	CGContextFillRect(context, rect);
	
	[$newsImage drawInRect:CGRectMake(0.f, 0.f, [self bounds].size.width, 130.f)];

	CGColorRef textColor = [[UIColor blackColor] CGColor];

	NSString *systemFont = [[UIFont systemFontOfSize:1.f] fontName];
	CTFontRef bodyFont = CTFontCreateWithName((CFStringRef)systemFont, 16.f, NULL);
	CTFontRef headFont = CTFontCreateCopyWithSymbolicTraits(bodyFont, 18.f, NULL, kCTFontBoldTrait, kCTFontBoldTrait);

	NSDictionary *fontAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
		(id)bodyFont, (id)kCTFontAttributeName,
		textColor, (id)kCTForegroundColorAttributeName,
		nil];
	NSDictionary *boldFontAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
		(id)headFont, (id)kCTFontAttributeName,
		textColor, (id)kCTForegroundColorAttributeName,
		nil];
	CFRelease(bodyFont);
	CFRelease(headFont);
	
	NSAttributedString *titleString = [[NSAttributedString alloc] initWithString:$newsTitle attributes:boldFontAttributes];
	NSAttributedString *subtitleString = [[NSAttributedString alloc] initWithString:$newsSubtitle attributes:fontAttributes];

	CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)titleString);
	[titleString release];
	
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextTranslateCTM(context, 0, [self bounds].size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	
	CGContextSetTextPosition(context, 5.f, [self bounds].size.height - 150.f);
	CTLineDraw(line, context);
	CFRelease(line);

	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)subtitleString);
	[subtitleString release];
	
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathAddRect(path, NULL, CGRectMake(5.f, 6.f, [self bounds].size.width - 10.f, [self bounds].size.height - 160.f));
	CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, NULL);
	CFRelease(framesetter);

	CGContextSetTextPosition(context, 0.f, 0.f); // idk if i need this but it works
	CTFrameDraw(frame, context);
	CFRelease(frame);

	if (highlighted) {
		[UIColorFromHexWithAlpha(0x7c7c7c, 0.4) setFill];
		CGContextFillRect(context, rect);
	}	
}

- (void)dealloc {
	[$newsImage release];
	[$newsTitle release];
	[$newsSubtitle release];

	[super dealloc];
}
@end

/* }}} */

/* Grades Controller {{{ */
// To be honest, I don't like this.
// We should use recursion. Recursive display of the tree, recursive building of the tree, etc.
// I doubt Porto will ever require/do such thing (due to their css class naming, I doubt their system support recursion),
// but I guess we should be better than them and implement this.
// Maybe a finish-up update before release?

// Yay averages.
// This is a node.
// GradeContainer sounds better than GradeNode.
// TODO: Make it impossible for Bonus Containers to call inappropriate methods 'by mistake'. Same for $NoGraders.
@implementation GradeContainer
@synthesize name, grade, value, average, subGradeContainers, subBonusContainers, weight, debugLevel, superContainer, isBonus, section;

- (id)init {
	if ((self = [super init])) {
		debugLevel = 0;
		isBonus = NO;
	}

	return self;
}

- (NSInteger)totalWeight {
	NSInteger ret = 0;
	for (GradeContainer *container in [self subGradeContainers])
		ret += [container weight];

	return ret;
}

- (CGFloat)$gradePercentage {
	if ([grade isEqualToString:@"$NoGrade"] || [value isEqualToString:@"$NoGrade"]) return 0.f;
	return [grade floatValue]/[value floatValue]*100;
}

- (BOOL)isAboveAverage {
	return [self $gradePercentage] >= kPortoAverage;
}

- (NSString *)gradePercentage {
	return [NSString stringWithFormat:@"%.0f%%", [self $gradePercentage]];
}

- (void)calculateGradeFromSubgrades {
	NSInteger gradeSum = 0;
	for (GradeContainer *container in [self subGradeContainers]) {
		if ([[container grade] isEqualToString:@"$NoGrade"]) continue;
		gradeSum += [[container grade] floatValue] * [container weight];
	}
	
	[self setGrade:[NSString stringWithFormat:@"%.2f", (double)gradeSum / [self totalWeight]]];
}

- (float)gradeInSupercontainer {
	if ([[self grade] isEqualToString:@"$NoGrade"]) return 0.f;

	NSInteger superTotalWeight = [[self superContainer] totalWeight];
	return [[self grade] floatValue] * [self weight] / superTotalWeight;
}

- (void)makeValueTen {
	[self setValue:[@"10,00" americanFloat]];
}

- (void)calculateAverageFromSubgrades {
	NSInteger averageSum = 0;
	for (GradeContainer *container in [self subGradeContainers]) {
		if ([[container average] isEqualToString:@"$NoGrade"]) continue;
		averageSum += [[container average] floatValue] * [container weight];
	}
	
	[self setAverage:[NSString stringWithFormat:@"%.2f", (double)averageSum / [self totalWeight]]];
}

- (NSInteger)indexAtSupercontainer {
	return [[[self superContainer] subGradeContainers] indexOfObject:self];
}

- (void)dealloc {
	[name release];
	[grade release];
	[value release];
	[average release];
	[subGradeContainers release];
	[subBonusContainers release];
	[superContainer release];

	[super dealloc];
}

// debug. don't complain :p
- (NSString *)description {
	NSMutableString *tabString = [[[NSMutableString alloc] initWithString:@""] autorelease];
	for (int i=0; i<[self debugLevel]; i++) [tabString appendString:@"\t"];

	NSString *selfstr = [NSString stringWithFormat:@"%@<GradeContainer: %p> (%@): %@/%@(%d) + %@", tabString, self, [self name], [self grade], [self value], [self weight], [self average]];
	NSMutableString *mutableString = [[[NSMutableString alloc] initWithString:[selfstr stringByAppendingString:@"\n"]] autorelease];
	
	for (GradeContainer *container in [self subGradeContainers]) {
		NSString *containerstr = [container description];
		[mutableString appendString:containerstr];
	}

	return mutableString;
}

- (void)attemptToFixValues {
	for (GradeContainer *container in [self subGradeContainers]) {
		if ([[container value] isEqualToString:@"$NoGrade"]) {
			int undefinedSiblings = 0;
			float valueSum = 0.f;

			for (GradeContainer *sibling in [[container superContainer] subGradeContainers]) {
				if ([[sibling value] isEqualToString:@"$NoGrade"]) undefinedSiblings++;
				else valueSum += [[sibling value] floatValue];
			}
			
			if (undefinedSiblings == 1) {
				[container setValue:[NSString stringWithFormat:@"%f", 10.f - valueSum]];
			}
		}

		[container attemptToFixValues];
	}
}
@end

// FIXME: Review ranges on both classes.
@implementation SubjectTableHeaderView
- (void)drawDataZoneRect:(CGRect)rect textColor:(CGColorRef)textColor dataFont:(CTFontRef)dataFont boldFont:(CTFontRef)boldFont inContext:(CGContextRef)context {
	CGFloat zoneWidth2 = rect.size.width/4;
	
	NSString *gradeString__ = [[[self container] grade] isEqualToString:@"$NoGrade"] ? @"N/A" : [[self container] grade];
	CFAttributedStringRef gradeString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Nota\n" stringByAppendingString:gradeString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange gradeContentRange = CFRangeMake(5, CFAttributedStringGetLength(gradeString_)-5);
	CFAttributedStringRef weightString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Peso\n" stringByAppendingString:[NSString stringWithFormat:@"%d", [[self container] weight]]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange weightContentRange = CFRangeMake(5, CFAttributedStringGetLength(weightString_)-5);
	NSString *averageString__ = [[[self container] average] isEqualToString:@"$NoGrade"] ? @"N/A" : [[self container] average];
	CFAttributedStringRef averageString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Média\n" stringByAppendingString:averageString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange averageContentRange = CFRangeMake(5, CFAttributedStringGetLength(averageString_)-5);
	NSString *totalString__ = [[[self container] grade] isEqualToString:@"$NoGrade"] ? @"N/A" : [NSString stringWithFormat:@"%.2f", [[self container] gradeInSupercontainer]];
	CFAttributedStringRef totalString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Total\n" stringByAppendingString:totalString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange totalContentRange = CFRangeMake(5, CFAttributedStringGetLength(totalString_)-5);

	CFMutableAttributedStringRef gradeString = CFAttributedStringCreateMutableCopy(NULL, 0, gradeString_);
	CFAttributedStringRemoveAttribute(gradeString, gradeContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(gradeString, gradeContentRange, kCTFontAttributeName, boldFont);
	CFRelease(gradeString_);

	CFMutableAttributedStringRef weightString = CFAttributedStringCreateMutableCopy(NULL, 0, weightString_);
	CFAttributedStringRemoveAttribute(weightString, weightContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(weightString, weightContentRange, kCTFontAttributeName, boldFont);
	CFRelease(weightString_);

	CFMutableAttributedStringRef averageString = CFAttributedStringCreateMutableCopy(NULL, 0, averageString_);
	CFAttributedStringRemoveAttribute(averageString, averageContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(averageString, averageContentRange, kCTFontAttributeName, boldFont);
	CFRelease(averageString_);

	CFMutableAttributedStringRef totalString = CFAttributedStringCreateMutableCopy(NULL, 0, totalString_);
	CFAttributedStringRemoveAttribute(totalString, totalContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(totalString, totalContentRange, kCTFontAttributeName, boldFont);
	CFRelease(totalString_);
	
	CTFramesetterRef gradeFramesetter = CTFramesetterCreateWithAttributedString(gradeString); CFRelease(gradeString);
	CTFramesetterRef weightFramesetter = CTFramesetterCreateWithAttributedString(weightString); CFRelease(weightString);
	CTFramesetterRef averageFramesetter = CTFramesetterCreateWithAttributedString(averageString); CFRelease(averageString);
	CTFramesetterRef totalFramesetter = CTFramesetterCreateWithAttributedString(totalString); CFRelease(totalString);
	
	CGRect gradeRect = CGRectMake(rect.origin.x, 0.f, zoneWidth2, rect.size.height);
	CGRect weightRect = CGRectMake(rect.origin.x + zoneWidth2, 0.f, zoneWidth2, rect.size.height);
	CGRect averageRect = CGRectMake(rect.origin.x + zoneWidth2*2, 0.f, zoneWidth2, rect.size.height);
	CGRect totalRect = CGRectMake(rect.origin.x + zoneWidth2*3, 0.f, zoneWidth2, rect.size.height);

	DrawFramesetter(context, gradeFramesetter, gradeRect); CFRelease(gradeFramesetter);
	DrawFramesetter(context, weightFramesetter, weightRect); CFRelease(weightFramesetter);
	DrawFramesetter(context, averageFramesetter, averageRect); CFRelease(averageFramesetter);
	DrawFramesetter(context, totalFramesetter, totalRect); CFRelease(totalFramesetter);
}
@end

@implementation SubjectTableViewCellContentView
- (void)drawDataZoneRect:(CGRect)rect textColor:(CGColorRef)textColor dataFont:(CTFontRef)dataFont boldFont:(CTFontRef)boldFont inContext:(CGContextRef)context {
	CGFloat zoneWidth2 = rect.size.width / 5;
	
	CFAttributedStringRef gradeString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Nota\n" stringByAppendingString:[[self container] grade]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange gradeContentRange = CFRangeMake(5, CFAttributedStringGetLength(gradeString_)-5);
	CFAttributedStringRef valueString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Valor\n" stringByAppendingString:[[self container] value]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange valueContentRange = CFRangeMake(5, CFAttributedStringGetLength(valueString_)-5);
	CFAttributedStringRef percentString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"%\n" stringByAppendingString:[[self container] gradePercentage]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange percentContentRange = CFRangeMake(2, CFAttributedStringGetLength(percentString_)-2);
	CFAttributedStringRef averageString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Média\n" stringByAppendingString:[[self container] average]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange averageContentRange = CFRangeMake(5, CFAttributedStringGetLength(averageString_)-5);
	CFAttributedStringRef totalString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Total\n" stringByAppendingString:[NSString stringWithFormat:@"%.2f", [[self container] gradeInSupercontainer]]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange totalContentRange = CFRangeMake(5, CFAttributedStringGetLength(totalString_)-5);

	CFMutableAttributedStringRef gradeString = CFAttributedStringCreateMutableCopy(NULL, 0, gradeString_);
	CFAttributedStringRemoveAttribute(gradeString, gradeContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(gradeString, gradeContentRange, kCTFontAttributeName, boldFont);
	CFRelease(gradeString_);

	CFMutableAttributedStringRef valueString = CFAttributedStringCreateMutableCopy(NULL, 0, valueString_);
	CFAttributedStringRemoveAttribute(valueString, valueContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(valueString, valueContentRange, kCTFontAttributeName, boldFont);
	CFRelease(valueString_);

	CFMutableAttributedStringRef percentString = CFAttributedStringCreateMutableCopy(NULL, 0, percentString_);
	CFAttributedStringRemoveAttribute(percentString, percentContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(percentString, percentContentRange, kCTFontAttributeName, boldFont);
	CFRelease(percentString_);
	
	CFMutableAttributedStringRef averageString = CFAttributedStringCreateMutableCopy(NULL, 0, averageString_);
	CFAttributedStringRemoveAttribute(averageString, averageContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(averageString, averageContentRange, kCTFontAttributeName, boldFont);
	CFRelease(averageString_);

	CFMutableAttributedStringRef totalString = CFAttributedStringCreateMutableCopy(NULL, 0, totalString_);
	CFAttributedStringRemoveAttribute(totalString, totalContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(totalString, totalContentRange, kCTFontAttributeName, boldFont);
	CFRelease(totalString_);
	
	CTFramesetterRef gradeFramesetter = CTFramesetterCreateWithAttributedString(gradeString); CFRelease(gradeString);
	CTFramesetterRef valueFramesetter = CTFramesetterCreateWithAttributedString(valueString); CFRelease(valueString);
	CTFramesetterRef percentFramesetter = CTFramesetterCreateWithAttributedString(percentString); CFRelease(percentString);
	CTFramesetterRef averageFramesetter = CTFramesetterCreateWithAttributedString(averageString); CFRelease(averageString);
	CTFramesetterRef totalFramesetter = CTFramesetterCreateWithAttributedString(totalString); CFRelease(totalString);
	
	CGRect gradeRect = CGRectMake(rect.origin.x, 0.f, zoneWidth2, rect.size.height);
	CGRect valueRect = CGRectMake(rect.origin.x + zoneWidth2, 0.f, zoneWidth2, rect.size.height);
	CGRect percentRect = CGRectMake(rect.origin.x + zoneWidth2*2, 0.f, zoneWidth2, rect.size.height);
	CGRect averageRect = CGRectMake(rect.origin.x + zoneWidth2*3, 0.f, zoneWidth2, rect.size.height);
	CGRect totalRect = CGRectMake(rect.origin.x + zoneWidth2*4, 0.f, zoneWidth2, rect.size.height);

	DrawFramesetter(context, gradeFramesetter, gradeRect); CFRelease(gradeFramesetter);
	DrawFramesetter(context, valueFramesetter, valueRect); CFRelease(valueFramesetter);
	DrawFramesetter(context, percentFramesetter, percentRect); CFRelease(percentFramesetter);
	DrawFramesetter(context, averageFramesetter, averageRect); CFRelease(averageFramesetter);
	DrawFramesetter(context, totalFramesetter, totalRect); CFRelease(totalFramesetter);
}
@end

#define TEXTFIELD_CENTER_HEIGHT_FIX 2.f
@implementation SubjectBonusTableHeaderView
- (id)initWithFrame:(CGRect)rect {
	if ((self = [super initWithFrame:rect])) {
		NSLog(@"VIEW RECT %@", NSStringFromCGRect(rect));

		$textField = [[UITextField alloc] initWithFrame:CGRectMake(rect.size.width/2 + rect.size.width/4, rect.size.height/2 - TEXTFIELD_CENTER_HEIGHT_FIX, rect.size.width/4, rect.size.height/2)];
		[$textField setPlaceholder:@"1.00"];
		[$textField setFont:[UIFont boldSystemFontOfSize:pxtopt(rect.size.height/2)]];
		[$textField setTextAlignment:NSTextAlignmentCenter];
		[$textField setContentVerticalAlignment:UIControlContentVerticalAlignmentCenter];
		[$textField setDelegate:self];
		[self addSubview:$textField];
	}
	
	return self;
}

- (void)setContainer:(GradeContainer *)container {
	// FIXME!!!!! Instead of using name use the id (which would be like Atv1, Atv2...)
	// NOTE: We call NSUserDefaults and not [[self container] value] because value has 1.0 as value so we couldn't tell whether it was real or the placeholder.
	NSString *text = [[NSUserDefaults standardUserDefaults] stringForKey:[[NSString stringWithFormat:@"BonusValue:%@:%@", [[container superContainer] name], [container name]] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:AmericanLocale]];
	NSLog(@"key ended up as %@, and text as %@", [[NSString stringWithFormat:@"BonusValue:%@:%@", [[container superContainer] name], [container name]] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:AmericanLocale], text);
	[$textField setText:[text length] > 0 ? text : nil];
        
        [super setContainer:container];
}

- (UITableView *)$tableView {
	UIView *tableView = self;
	while (![tableView isKindOfClass:[UITableView class]]) tableView = [tableView superview];

	return (UITableView *)tableView;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];		
}

- (void)keyboardWillShow:(NSNotification *)notification {
	UITableView *tableView = [self $tableView];

	CGFloat height = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
	NSTimeInterval duration = [[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	
	UIEdgeInsets edgeInsets = UIEdgeInsetsMake(0, 0, height - HEIGHT_OF_TABBAR, 0);
	[UIView animateWithDuration:duration animations:^{
		[tableView setContentInset:edgeInsets];
		[tableView setScrollIndicatorInsets:edgeInsets];
		[tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:NSNotFound inSection:[[self container] section]] atScrollPosition:UITableViewScrollPositionTop animated:YES];
	}];
}

- (void)keyboardWillHide:(NSNotification *)notification {
	UITableView *tableView = [self $tableView];
	
        NSTimeInterval duration = [[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];

	[UIView animateWithDuration:duration animations:^{
		[tableView setContentInset:UIEdgeInsetsZero];
		[tableView setScrollIndicatorInsets:UIEdgeInsetsZero];
	}];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	NSString *text = [[textField text] americanFloat];
	if ([text floatValue] == 0 || [text floatValue] < [[[self container] grade] floatValue]) text = [NSString string];
	else {
		text = [NSString stringWithFormat:@"%.2f", [text floatValue]];

		[[self container] setValue:text];

		UIView *subjectView = self;
		while (![subjectView isKindOfClass:[SubjectView class]]) subjectView = [subjectView superview];
		[(PieChartView *)[subjectView viewWithTag:500] updateBonusSliders];
	}
	
	[textField setText:[text isEqualToString:[NSString string]] ? nil : text];
	[[NSUserDefaults standardUserDefaults] setObject:text forKey:[[NSString stringWithFormat:@"BonusValue:%@:%@", [[[self container] superContainer] name], [[self container] name]] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:AmericanLocale]];
	[[NSUserDefaults standardUserDefaults] synchronize];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

- (void)drawDataZoneRect:(CGRect)rect textColor:(CGColorRef)textColor dataFont:(CTFontRef)dataFont boldFont:(CTFontRef)boldFont inContext:(CGContextRef)context {
	CGFloat zoneWidth2 = rect.size.width / 2;
	NSLog(@"zoneWidth2 = %f; rect.size.width = %f", zoneWidth2, rect.size.width);
	
	NSString *gradeString__ = [[[self container] grade] isEqualToString:@"$NoGrade"] ? @"N/A" : [[self container] grade];
	CFAttributedStringRef gradeString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Nota\n" stringByAppendingString:gradeString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange gradeContentRange = CFRangeMake(5, CFAttributedStringGetLength(gradeString_)-5);
	
	CFMutableAttributedStringRef gradeString = CFAttributedStringCreateMutableCopy(NULL, 0, gradeString_);
	CFAttributedStringRemoveAttribute(gradeString, gradeContentRange, kCTFontAttributeName);
	CFAttributedStringSetAttribute(gradeString, gradeContentRange, kCTFontAttributeName, boldFont);
	CFRelease(gradeString_);
	
	CTFramesetterRef gradeFramesetter = CTFramesetterCreateWithAttributedString(gradeString); CFRelease(gradeString);
	CTFramesetterRef valueFramesetter = CreateFramesetter(dataFont, textColor, CFSTR("Valor\n"), NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);

	DrawFramesetter(context, gradeFramesetter, CGRectMake(rect.origin.x, 0.f, zoneWidth2, rect.size.height)); CFRelease(gradeFramesetter);
	DrawFramesetter(context, valueFramesetter, CGRectMake(rect.origin.x + zoneWidth2, 0.f, zoneWidth2, rect.size.height)); CFRelease(valueFramesetter);
}
@end

@implementation TestView
@synthesize container;

- (void)drawRect:(CGRect)rect {
	//NSLog(@"-[TestView drawRect:%@] with %@", NSStringFromCGRect(rect), NSStringFromClass([self class]));
	
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextTranslateCTM(context, 0, self.bounds.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	
	// FIXME: hacking my own apis; not a good sign.
	bool isEven = [container indexAtSupercontainer] % 2 == 0;
	if (rect.size.height != 44.f) isEven = !isEven;

	[(isEven ? UIColorFromHexWithAlpha(0xfafafa, 1.f) : [UIColor whiteColor]) setFill];
	CGContextFillRect(context, rect);
	
	CGFloat zoneHeight = rect.size.height/2;
	CGFloat zoneWidth = [container isBonus] ? rect.size.width/2 : rect.size.width/3;
	
	// ZONE 1
	UIColor *colorForGrade = [[container grade] isEqualToString:@"$NoGrade"] || [container isBonus] ? UIColorFromHexWithAlpha(0x708090, 1.f) : ColorForGrade([container $gradePercentage]/10.f);
	[colorForGrade setFill];
	CGRect circleRect = CGRectMake(8.f, zoneHeight/2, zoneHeight, zoneHeight);
	CGContextFillEllipseInRect(context, circleRect);
	
	CGColorRef textColor = [[UIColor blackColor] CGColor];

	NSString *systemFont = [[UIFont systemFontOfSize:1.f] fontName];
	CTFontRef dataFont = CTFontCreateWithName((CFStringRef)systemFont, pxtopt(zoneHeight), NULL);
	CTFontRef boldFont = CTFontCreateCopyWithSymbolicTraits(dataFont, pxtopt(zoneHeight), NULL, kCTFontBoldTrait, kCTFontBoldTrait);
	
	NSString *gradeString = [[container grade] isEqualToString:@"$NoGrade"] ? @"N/A" : [container grade];
	CTFramesetterRef fpGradeFramesetter = CreateFramesetter(boldFont, textColor, (CFStringRef)gradeString, NO, kCTLineBreakByTruncatingTail);
	CGSize gradeRequirement = CTFramesetterSuggestFrameSizeWithConstraints(fpGradeFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
	gradeRequirement.width += 5.f;

	CTFramesetterRef examFramesetter = CreateFramesetter(dataFont, textColor, (CFStringRef)[container name], NO, kCTLineBreakByTruncatingTail);
	CGFloat examWidth = circleRect.origin.x + circleRect.size.width + 8.f;
	CGRect examRect = CGRectMake(examWidth, zoneHeight/2, zoneWidth - examWidth - gradeRequirement.width, zoneHeight);
	DrawFramesetter(context, examFramesetter, examRect);
	CFRelease(examFramesetter);
	
	DrawFramesetter(context, fpGradeFramesetter, CGRectMake(examRect.origin.x + examRect.size.width, zoneHeight/2, gradeRequirement.width, zoneHeight));
	CFRelease(fpGradeFramesetter);

	// ZONE 2
	[self drawDataZoneRect:CGRectMake(zoneWidth, 0.f, zoneWidth, rect.size.height) textColor:textColor dataFont:dataFont boldFont:boldFont inContext:context];
	
	if ([container isBonus]) {
		CFRelease(dataFont);
		CFRelease(boldFont);
		
		return;
	}

	// ZONE 3
	CTFramesetterRef gradeLabelFramesetter = CreateFramesetter(boldFont, textColor, CFSTR("Nota"), NO, kCTLineBreakByTruncatingTail);
	CTFramesetterRef averageLabelFramesetter = CreateFramesetter(boldFont, textColor, CFSTR("Média"), NO, kCTLineBreakByTruncatingTail);
	
	CGSize averageSize = CTFramesetterSuggestFrameSizeWithConstraints(averageLabelFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
	averageSize.width += 5.f;
	DrawFramesetter(context, gradeLabelFramesetter, CGRectMake(zoneWidth * 2 + 5.f, zoneHeight, averageSize.width, zoneHeight)); CFRelease(gradeLabelFramesetter);
	DrawFramesetter(context, averageLabelFramesetter, CGRectMake(zoneWidth * 2 + 5.f, 0.f, averageSize.width, zoneHeight)); CFRelease(averageLabelFramesetter);
	
	UIColor *emptyColor = UIColorFromHexWithAlpha(0xC0C0C0, 1.f);
	[emptyColor setFill];
	
	CGFloat baseGraphWidth = zoneWidth - averageSize.width - 10.f;
	CGRect baseGraphRect = CGRectMake(zoneWidth * 2 + averageSize.width + 5.f, 0.f, baseGraphWidth, zoneHeight - 4.f);

	CGContextFillRect(context, (CGRect){{baseGraphRect.origin.x, 2.f}, baseGraphRect.size});
	CGContextFillRect(context, (CGRect){{baseGraphRect.origin.x, 6.f + baseGraphRect.size.height}, baseGraphRect.size});

	CGFloat gradeBarWidth = [[container grade] floatValue] / [[container value] floatValue] * baseGraphWidth;
	CGFloat averageBarWidth = [[container average] floatValue] / [[container value] floatValue] * baseGraphWidth;

	[ColorForGrade([[container average] floatValue], NO) setFill];
	CGContextFillRect(context, (CGRect){{baseGraphRect.origin.x, 2.f}, {averageBarWidth, baseGraphRect.size.height}});
	[ColorForGrade([[container grade] floatValue]) setFill];
	CGContextFillRect(context, (CGRect){{baseGraphRect.origin.x, 6.f + baseGraphRect.size.height}, {gradeBarWidth, baseGraphRect.size.height}});
	
	CTFontRef smallerFont = CTFontCreateCopyWithSymbolicTraits(dataFont, pxtopt(baseGraphRect.size.height), NULL, kCTFontBoldTrait, kCTFontBoldTrait);

	CTFramesetterRef gradeBarFramesetter = CreateFramesetter(smallerFont, [[UIColor whiteColor] CGColor], (CFStringRef)gradeString, NO, kCTLineBreakByTruncatingTail);
	CGFloat requiredWidth = CTFramesetterSuggestFrameSizeWithConstraints(gradeBarFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL).width;
	CGFloat xOrigin = baseGraphRect.origin.x + gradeBarWidth - requiredWidth - 3.f;
	CGRect gradeBarRect = CGRectMake(xOrigin > baseGraphRect.origin.x ? xOrigin : baseGraphRect.origin.x+2.f, 6.f + baseGraphRect.size.height, requiredWidth, baseGraphRect.size.height);
	DrawFramesetter(context, gradeBarFramesetter, gradeBarRect); CFRelease(gradeBarFramesetter);

	NSString *averageString = [[container average] isEqualToString:@"$NoGrade"] ? @"N/A" : [container average];
	CTFramesetterRef averageBarFramesetter = CreateFramesetter(smallerFont, [[UIColor whiteColor] CGColor], (CFStringRef)averageString, NO, kCTLineBreakByTruncatingTail);
	CGFloat requiredWidthAvg = CTFramesetterSuggestFrameSizeWithConstraints(averageBarFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL).width;
	CGFloat xOriginAvg = baseGraphRect.origin.x + averageBarWidth - requiredWidth - 3.f;
	CGRect averageBarRect = CGRectMake(xOriginAvg > baseGraphRect.origin.x ? xOriginAvg : baseGraphRect.origin.x+2.f, 2.f, requiredWidthAvg, baseGraphRect.size.height);
	DrawFramesetter(context, averageBarFramesetter, averageBarRect); CFRelease(averageBarFramesetter);
	
	CFRelease(smallerFont);
	CFRelease(dataFont);
	CFRelease(boldFont);
}

- (void)drawDataZoneRect:(CGRect)rect textColor:(CGColorRef)textColor dataFont:(CTFontRef)dataFont boldFont:(CTFontRef)boldFont inContext:(CGContextRef)context {
	return;
}

- (void)dealloc {
	[container release];
	[super dealloc];
}
@end

@implementation SubjectView
- (id)initWithFrame:(CGRect)frame container:(GradeContainer *)container {
	if ((self = [super initWithFrame:frame])) {
		$container = [container retain];
		[self setBackgroundColor:[UIColor whiteColor]];

		NoButtonDelayTableView *tableView = [[NoButtonDelayTableView alloc] initWithFrame:[self bounds] style:UITableViewStylePlain];
		[tableView setDataSource:self];
		[tableView setDelegate:self];
		[tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
		[self addSubview:tableView];
		[tableView release];
		
		// FIXME: Use CoreText instead of attributed UILabels.
		// (I'm asking myself why I did those in the first place.)
		UIView *tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, [tableView bounds].size.width, 54.f)];
		CGFloat halfHeight = [tableHeaderView bounds].size.height/2;
		
		UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(5.f, 0.f, ([self bounds].size.width/3)*2, 54.f)];
		[nameLabel setBackgroundColor:[UIColor clearColor]];
		[nameLabel setTextColor:[UIColor blackColor]];
		[nameLabel setFont:[UIFont boldSystemFontOfSize:pxtopt(halfHeight)]];
		[nameLabel setNumberOfLines:0];
		[nameLabel setText:[container name]];
		[tableHeaderView addSubview:nameLabel];
		/*CGFloat width = [nameLabel bounds].size.width;
		[nameLabel sizeToFit];
		[nameLabel setFrame:CGRectMake(nameLabel.bounds.origin.x, nameLabel.bounds.origin.y, width, nameLabel.bounds.size.height)];*/
		[nameLabel release];

		if (![[container grade] isEqualToString:@"$NoGrade"]) {
			NSString *gradeTitle = @"Nota: ";
			NSString *averageTitle = @"Média: ";

			NSMutableAttributedString *gradeAttributedString = [[NSMutableAttributedString alloc] initWithString:[gradeTitle stringByAppendingString:[container grade]]];
			[gradeAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:pxtopt(24.f)] range:NSMakeRange(0, [gradeTitle length])];
			[gradeAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:pxtopt(24.f)] range:NSMakeRange([gradeTitle length], [gradeAttributedString length]-[gradeTitle length])];
			
			NSMutableAttributedString *averageAttributedString = [[NSMutableAttributedString alloc] initWithString:[averageTitle stringByAppendingString:[container average]]];
			[averageAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:pxtopt(24.f)] range:NSMakeRange(0, [averageTitle length])];
			[averageAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:pxtopt(24.f)] range:NSMakeRange([averageTitle length], [averageAttributedString length]-[averageTitle length])];

			UILabel *gradeLabel = [[UILabel alloc] initWithFrame:CGRectMake([nameLabel bounds].size.width + 5.f, 0.f, [self bounds].size.width/3, 27.f)];
			[gradeLabel setBackgroundColor:[UIColor clearColor]];
			[gradeLabel setTextColor:[UIColor blackColor]];
			[gradeLabel setAttributedText:gradeAttributedString];
			[tableHeaderView addSubview:gradeLabel];
			[gradeLabel release];

			UILabel *averageLabel = [[UILabel alloc] initWithFrame:CGRectMake([nameLabel bounds].size.width + 5.f, 22.f, [self bounds].size.width/3, 27.f)];
			[averageLabel setBackgroundColor:[UIColor clearColor]];
			[averageLabel setTextColor:[UIColor blackColor]];
			[averageLabel setAttributedText:averageAttributedString];
			[tableHeaderView addSubview:averageLabel];
			[averageLabel release];
		}
		
		[tableView setTableHeaderView:tableHeaderView];
		[tableHeaderView release];
		
		NSMutableArray *pieces = [NSMutableArray array];
		for (GradeContainer *subContainer in [$container subGradeContainers]) {
			PieChartPiece *piece = [[[PieChartPiece alloc] init] autorelease];
			[piece setPercentage:[subContainer gradeInSupercontainer]*10.f];
			[piece setContainer:subContainer];
			[piece setColor:RandomColorHex()];
			[piece setText:[subContainer name]];
			[piece setIsBonus:NO];

			[pieces addObject:piece];
		}
		for (GradeContainer *bonusContainer in [$container subBonusContainers]) {
			PieChartPiece *piece = [[[PieChartPiece alloc] init] autorelease];
			[piece setPercentage:[[bonusContainer grade] floatValue] * 10.f];
			[piece setContainer:bonusContainer];
			[piece setColor:RandomColorHex()];
			[piece setText:[bonusContainer name]];
			[piece setIsBonus:YES];

			[pieces addObject:piece];
		}
		
		PieChartPiece *emptyPiece = [[[PieChartPiece alloc] init] autorelease];
		[emptyPiece setPercentage:0.f];
		[emptyPiece setColor:0x000000];
		[emptyPiece setText:@"Empty"];
		
		CGFloat rowsHeight = [pieces count] * [PieChartView rowHeight] + ([PieChartView extraHeight] + kPieChartViewInset*2);
		CGFloat minHeight = [PieChartView minHeightForRadius:55.f];
		PieChartView *mainPieChart = [[PieChartView alloc] initWithFrame:CGRectMake(0.f, 0.f, [tableView bounds].size.width, rowsHeight < minHeight ? minHeight : rowsHeight) pieces:pieces count:[[$container subGradeContainers] count] radius:55.f emptyPiece:emptyPiece];
		[mainPieChart setTag:500];
		[mainPieChart setDelegate:self];
		
		UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, [tableView bounds].size.width, [mainPieChart bounds].size.height)];
		[footerView addSubview:mainPieChart];
		[mainPieChart release];

		[tableView setTableFooterView:footerView];
		[footerView release];
	}

	return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [[$container subGradeContainers] count] + [[$container subBonusContainers] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section >= [[$container subGradeContainers] count]) return 0;
	return [[[[$container subGradeContainers] objectAtIndex:section] subGradeContainers] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PortoAppSubjectViewTableViewCell"];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PortoAppSubjectViewTableViewCell"] autorelease];
		
		// FIXME: Remove this constant 32.f, and 55.
		UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0.f, 0.f, tableView.bounds.size.width, 32.f)];
		[scrollView setContentSize:CGSizeMake(scrollView.bounds.size.width * 3, scrollView.bounds.size.height)];
		[scrollView setScrollsToTop:NO];
		[scrollView setShowsHorizontalScrollIndicator:NO];
		[scrollView setPagingEnabled:YES];
		[scrollView setTag:55];
		
		SubjectTableViewCellContentView *contentView = [[SubjectTableViewCellContentView alloc] initWithFrame:CGRectMake(0.f, 0.f, [scrollView contentSize].width, [scrollView contentSize].height)];
		[scrollView addSubview:contentView];
		[contentView release];

		[[cell contentView] addSubview:scrollView];
		[scrollView release];
	}
	
	SubjectTableViewCellContentView *contentView_ = (SubjectTableViewCellContentView *)[[[[cell contentView] viewWithTag:55] subviews] objectAtIndex:0];
	[contentView_ setContainer:[[[[$container subGradeContainers] objectAtIndex:[indexPath section]] subGradeContainers] objectAtIndex:[indexPath row]]];

	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 32.f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return 44.f;
}

// TODO: UITableViewHeaderFooterView is iOS6+. I dislike having to rely on apis > iOS 5. :(
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	BOOL isBonus = section >= [[$container subGradeContainers] count];
	NSString *identifier = isBonus ? @"PortoAppSubjectViewTableHeaderViewBonus" : @"PortoAppSubjectViewTableHeaderViewGrade";

	UITableViewHeaderFooterView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:identifier];
	if (headerView == nil) {
		headerView = [[[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:identifier] autorelease];

		UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0.f, 0.f, tableView.bounds.size.width, 44.f)];
		[scrollView setContentSize:CGSizeMake(scrollView.bounds.size.width * (isBonus ? 2 : 3), scrollView.bounds.size.height)];
		[scrollView setScrollsToTop:NO]; 
		[scrollView setShowsHorizontalScrollIndicator:NO];
		[scrollView setPagingEnabled:YES];
		[scrollView setTag:5];

		Class testViewClass = isBonus ? [SubjectBonusTableHeaderView class] : [SubjectTableHeaderView class];
		CGRect frame = CGRectMake(0.f, 0.f, [scrollView contentSize].width, [scrollView contentSize].height);
		TestView *testView = [[testViewClass alloc] initWithFrame:frame];
		[testView setTag:6];
		[scrollView addSubview:testView];
		[testView release];
		
		[[headerView contentView] addSubview:scrollView];
		[scrollView release];
	}
	
	GradeContainer *container = isBonus ? [[$container subBonusContainers] objectAtIndex:section - [[$container subGradeContainers] count]] : [[$container subGradeContainers] objectAtIndex:section];
	[(TestView *)[[headerView viewWithTag:5] viewWithTag:6] setContainer:container];
	[(UIScrollView *)[headerView viewWithTag:5] setContentOffset:CGPointMake(0.f, 0.f)];
	[[[headerView viewWithTag:5] viewWithTag:6] setNeedsDisplay];
	return headerView;
}

- (void)dealloc {
	[$container release];

	[super dealloc];
}
@end

// URGENT FIXME Add a page control.
@implementation GradesListViewController
@synthesize year = $year, period = $period;

- (id)init {
	return nil;
}

- (GradesListViewController *)initWithYear:(NSString *)year period:(NSString *)period viewState:(NSString *)viewState eventValidation:(NSString *)eventValidation {
	if ((self = [super initWithIdentifier:@"GradesListView"])) {
		$viewState = [viewState retain];
		$eventValidation = [eventValidation retain];

		[self setYear:year];
		[self setPeriod:period];

		$rootContainer = nil;
	}

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Notas"];
}

- (void)reloadData {
	[super reloadData];
	SessionController *sessionController = [SessionController sharedInstance];
	
	//#define READ_FROM_LOCAL_DEBUG_HTML
	#ifdef READ_FROM_LOCAL_DEBUG_HTML
	NSData *data = [NSData dataWithContentsOfFile:@"/Users/BobNelson/Documents/Projects/PortoApp/3rdp.html"];
	#else
	NSString *request = [[NSDictionary dictionaryWithObjectsAndKeys:
		[sessionController gradeID], @"token",
		$year, @"ctl00$ContentPlaceHolder1$ddlAno",
		$period, @"ctl00$ContentPlaceHolder1$ddlEtapa",
		@"Visualizar", @"ctl00$ContentPlaceHolder1$btnVoltarLista",
		$viewState, @"__VIEWSTATE",
		$eventValidation, @"__EVENTVALIDATION",
		nil] urlEncodedString];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://notasparciais.portoseguro.org.br/notasparciais.aspx?%@", request]];
	
	NSURLResponse *response;
	NSError *error;

	NSData *data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:&error];
	#endif

	// i used this because 3rd period of 2013 was going to be concluded
	// so i still needed to test this on an incomplete period.
	// so i saved this html file. i know it's a horrible test with few cases, but i'll be creative etc.
	//#define SAVE_GRADE_HTML
	#ifdef SAVE_GRADE_HTML
	[data writeToFile:@"/Users/BobNelson/Documents/Projects/PortoApp/datak.html" atomically:NO];
	#endif

	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
	XMLElement *divGeral = [document firstElementMatchingPath:@"/html/body/form[@id='form1']/div[@class='page ui-corner-bottom']/div[@class='body']/div[@id='updtPnl1']/div[@id='ContentPlaceHolder1_divGeral']"];
	
	XMLElement *table = [divGeral firstElementMatchingPath:@"./table[@id='ContentPlaceHolder1_dlMaterias']"];
	NSArray *subjectElements = [table elementsMatchingPath:@"./tr/td/div[@class='container']"];
	
	$rootContainer = [[GradeContainer alloc] init];
	[$rootContainer setDebugLevel:0];
	[$rootContainer setWeight:1];
	[$rootContainer setName:@"Nota Total"];
	[$rootContainer makeValueTen];
	
	NSMutableArray *subjectContainers = [NSMutableArray array];
	for (XMLElement *container in subjectElements) {
		GradeContainer *subjectContainer = [[[GradeContainer alloc] init] autorelease];
		[subjectContainer setSuperContainer:$rootContainer];
		[subjectContainer setDebugLevel:1];
		[subjectContainer makeValueTen];
		[subjectContainer setWeight:1];
		[subjectContainer setIsBonus:NO];
		
		NSString *subjectName = [[container firstElementMatchingPath:@"./h2[@class='fleft m10r ']/span"] content];
		subjectName = [subjectName stringByReplacingOccurrencesOfString:@"LÍNG. ESTR. MOD. " withString:@""]; // remove LING ESTR MOD. I can now live in peace.
		// B-Zug Fächer handeln
		// denn ich kann
		if ([subjectName hasPrefix:@"*"]) {
			subjectName = [[subjectName substringFromIndex:1] substringToIndex:[subjectName length]-2];
			subjectName = [subjectName stringByAppendingString:@" \ue50e"]; // \ue50e is meant to be a DE flag.
		}
		else if ([subjectName isEqualToString:@"ARTES VISUAIS"]) continue; // Fix a (porto) issue where we get DE + non-DE Kunst (one would hope this doesn't break other dudes' grades)

		[subjectContainer setName:subjectName];
		
		NSString *totalGrade_ = [[container firstElementMatchingPath:@"./h2[@class='fright ']/span/span[1]/span"] content];
		NSString *totalGrade;
		if ([totalGrade_ isGrade]) totalGrade = [[totalGrade_ componentsSeparatedByString:@":"] objectAtIndex:1];
		else totalGrade = @"$NoGrade";
		[subjectContainer setGrade:[totalGrade americanFloat]];

		NSString *averageGrade_ = [[container firstElementMatchingPath:@"./h2[@class='fright ']/span/span[2]/span"] content];
		NSString *averageGrade;
		if ([averageGrade_ isGrade]) averageGrade = [[averageGrade_ componentsSeparatedByString:@": "] objectAtIndex:1];
		else averageGrade = @"$NoGrade";
		[subjectContainer setAverage:[averageGrade americanFloat]];
		
		// TODO: Optimize this into a recursive routine.
		NSArray *subjectGrades = [[container firstElementMatchingPath:@"./div/table[starts-with(@id, 'ContentPlaceHolder1_dlMaterias_gvNotas')]"] elementsMatchingPath:@"./tr[@class!='headerTable1 p3']"];
		NSMutableArray *subGradeContainers = [NSMutableArray array];
		for (XMLElement *subsection in subjectGrades) {
			GradeContainer *subGradeContainer = [[[GradeContainer alloc] init] autorelease];
			[subGradeContainer setSuperContainer:subjectContainer];
			[subGradeContainer setDebugLevel:2];
			[subGradeContainer makeValueTen];
			[subGradeContainer setIsBonus:NO];

			NSString *subsectionName = [[subsection firstElementMatchingPath:@"./td[2]"] content];
			NSArray *split = [subsectionName componentsSeparatedByString:@" - "];
			[subGradeContainer setName:[split objectAtIndex:1]];

			NSString *subsectionGrade = [[subsection firstElementMatchingPath:@"./td[3]"] content];
			if (![subsectionGrade isGrade]) subsectionGrade = @"$NoGrade";
			[subGradeContainer setGrade:[subsectionGrade americanFloat]];
			
			NSString *weightString = [split objectAtIndex:0];
			[subGradeContainer setWeight:[[weightString substringWithRange:NSMakeRange(3, 1)] integerValue]];
			
			NSString *subsectionAverage = [[subsection firstElementMatchingPath:@"./td[4]"] content];
			if (![subsectionAverage isGrade]) subsectionAverage = @"$NoGrade";
			[subGradeContainer setAverage:[subsectionAverage americanFloat]];
			
			NSMutableArray *subsubGradeContainers = [NSMutableArray array];
			XMLElement *tableTd = [subsection firstElementMatchingPath:@"./td[5]"];
			if (![[tableTd content] isEqualToString:@""]) {
				NSArray *subsectionSubGrades = [[tableTd firstElementMatchingPath:@"./div/div/div/table"] elementsMatchingPath:@"./tr[@class!='headerTable1 p3']"];
				for (XMLElement *subsubsection in subsectionSubGrades) {
					GradeContainer *subsubsectionGradeContainer = [[[GradeContainer alloc] init] autorelease];
					[subsubsectionGradeContainer setSuperContainer:subGradeContainer];
					[subsubsectionGradeContainer setDebugLevel:3];
					[subsubsectionGradeContainer setWeight:1];
					[subsubsectionGradeContainer setIsBonus:NO];
					
					NSString *subsubsectionName = [[[subsubsection firstElementMatchingPath:@"./td[1]"] content] substringFromIndex:5];
					[subsubsectionGradeContainer setName:subsubsectionName];
					NSString *subsubsectionGrade = [[subsubsection firstElementMatchingPath:@"./td[2]"] content];
					if (![subsubsectionGrade isGrade]) subsubsectionGrade = @"$NoGrade";
					[subsubsectionGradeContainer setGrade:[subsubsectionGrade americanFloat]];
					// Values are extremely required to calculate stuff. If we don't have it I'll consider it a flaw.
					NSString *subsubsectionValue = [[subsubsection firstElementMatchingPath:@"./td[3]"] content];
					if (![subsubsectionValue isGrade]) continue;
					[subsubsectionGradeContainer setValue:[subsubsectionValue americanFloat]];
					NSString *subsubsectionAverage = [[subsubsection firstElementMatchingPath:@"./td[4]"] content];
					if (![subsubsectionAverage isGrade]) subsubsectionAverage = @"$NoGrade";
					[subsubsectionGradeContainer setAverage:[subsubsectionAverage americanFloat]];

					[subsubGradeContainers addObject:subsubsectionGradeContainer];
				}
			}
			
			[subGradeContainer setSubGradeContainers:subsubGradeContainers];
			[subGradeContainers addObject:subGradeContainer];
		}

		NSMutableArray *subBonusContainers = [NSMutableArray array];
		NSArray *bonusGrades = [[container firstElementMatchingPath:@"./div/table[starts-with(@id, 'ContentPlaceHolder1_dlMaterias_gvAtividades')]"] elementsMatchingPath:@"./tr"];
		if (bonusGrades != nil) {
			for (XMLElement *subsection in bonusGrades) {
				GradeContainer *bonusContainer = [[[GradeContainer alloc] init] autorelease];
				[bonusContainer setSuperContainer:subjectContainer];
				[bonusContainer setDebugLevel:2];
				[bonusContainer setAverage:@"$NoGrade"];
				[bonusContainer setWeight:-1];
				[bonusContainer setIsBonus:YES];

				NSString *subsectionName = [[subsection firstElementMatchingPath:@"./td[2]"] content];
				NSArray *split = [subsectionName componentsSeparatedByString:@" - "];
				NSString *prepend = [[split objectAtIndex:1] rangeOfString:@"bonus" options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound ? @"Bônus " : @"";
				NSString *finalName = [prepend stringByAppendingString:[split objectAtIndex:1]];
				[bonusContainer setName:finalName];

				NSString *subsectionGrade = [[subsection firstElementMatchingPath:@"./td[3]"] content];
				if (![subsectionGrade isGrade]) subsectionGrade = @"$NoGrade";
				[bonusContainer setGrade:[subsectionGrade americanFloat]];
				
				NSString *valueText = [[NSUserDefaults standardUserDefaults] stringForKey:[[NSString stringWithFormat:@"BonusValue:%@:%@", subjectName, finalName] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:AmericanLocale]];
				NSLog(@"FINAL IS %@", finalName);
				NSLog(@"supposedly key %@ has value %@", [[NSString stringWithFormat:@"BonusValue:%@:%@", subjectName, finalName] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:AmericanLocale], valueText);
				[bonusContainer setValue:[valueText length] > 0 ? valueText : @"1.00"];
				NSLog(@"bc %@", [bonusContainer value]);

				[subBonusContainers addObject:bonusContainer];
			}
		}
		
		[subjectContainer setSubGradeContainers:subGradeContainers];
		[subjectContainer setSubBonusContainers:subBonusContainers];
		[subjectContainers addObject:subjectContainer];
	}

	[document release];
	
	[$rootContainer setSubGradeContainers:subjectContainers];
	[$rootContainer calculateGradeFromSubgrades];
	[$rootContainer calculateAverageFromSubgrades];
	
	/*      Cristina Santos: Olha só parabéns u.u
		Cristina Santos: Gostei de ver
	NSLog(@"%@", $rootContainer); */
        
	[self $performUIBlock:^{
		[self prepareContentView];
		[self displayContentView];
	}];
}

- (void)loadContentView {
	NoButtonDelayScrollView *scrollView = [[NoButtonDelayScrollView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[scrollView setBackgroundColor:[UIColor whiteColor]];
	[scrollView setScrollsToTop:NO];
	[scrollView setPagingEnabled:YES];

	$contentView = scrollView;
}

- (void)prepareContentView {
	NoButtonDelayScrollView *contentView = (NoButtonDelayScrollView *)$contentView;
	NSArray *subjectContainers = [$rootContainer subGradeContainers];

	CGRect subviewRect = CGRectMake(0.f, 0.f, [contentView bounds].size.width, [contentView bounds].size.height);
	for (GradeContainer *subject in subjectContainers) {
		SubjectView *subjectView = [[[SubjectView alloc] initWithFrame:subviewRect container:subject] autorelease];
		[contentView addSubview:subjectView];

		subviewRect.origin.x += subviewRect.size.width;
	}
	[contentView setContentSize:CGSizeMake(subviewRect.origin.x, [contentView bounds].size.height)];
}

- (void)dealloc {
	[$viewState release];
	[$eventValidation release];
	[$year release];
	[$period release];

	[super dealloc];
}
@end

@implementation GradesViewController
- (id)initWithIdentifier:(NSString *)identifier {
	if ((self = [super initWithIdentifier:identifier])) {
		$yearOptions = [[NSMutableArray alloc] init];
		$periodOptions = [[NSMutableDictionary alloc] init];

		$viewState = nil;
		$eventValidation = nil;
	}

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Notas"];
}

- (void)reloadData {
	[super reloadData];

	SessionController *sessionController = [SessionController sharedInstance];
	if (![sessionController hasSession]) [self displayFailViewWithImage:nil text:@"Sem autenticação.\nRealize um login no menu de Contas."];
	if (![sessionController gradeID]) {
		[self displayFailViewWithImage:nil text:@"Falha ao obter o ID de Notas.\n\nEstamos trabalhando para consertar este problema."];
		return;
	}
	
	if ($viewState != nil) [$viewState release];
	if ($eventValidation != nil) [$eventValidation release];
	$viewState = nil;
	$eventValidation = nil;

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://notasparciais.portoseguro.org.br/notasparciais.aspx?token=%@", [sessionController gradeID]]];
	NSURLResponse *response;
	NSData *data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:NULL];
	if (data == nil) {
		[self displayFailViewWithImage:nil text:@"Falha ao carregar página.\n\nCheque sua conexão de Internet."];
		return;
	}
	
	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
	NSArray *hiddenInputs = [document elementsMatchingPath:@"/html/body/form[@id='form1']/input[@type='hidden']"];
	for (XMLElement *input in hiddenInputs) {
		NSDictionary *attributes = [input attributes];
		if ([[attributes objectForKey:@"name"] isEqualToString:@"__VIEWSTATE"])
			$viewState = [[attributes objectForKey:@"value"] retain];
		else if ([[attributes objectForKey:@"name"] isEqualToString:@"__EVENTVALIDATION"])
			$eventValidation = [[attributes objectForKey:@"value"] retain];
	}

	if ($viewState == nil || $eventValidation == nil) {
		[self displayFailViewWithImage:nil text:@"Falha ao interpretar página (notasparciais.aspx:State/Validation)\n\nEstamos trabalhando para consertar este problema."];
		return;
	}
	
	NSString *m3tPath = @"/html/body/form[@id='form1']/div[@class='page ui-corner-bottom']/div[@class='body']/div[@id='updtPnl1']/div[@id='ContentPlaceHolder1_divGeral']/div[@class='container']/div[@class='m3t']";
	XMLElement *yearSelect = [document firstElementMatchingPath:[m3tPath stringByAppendingString:@"/select[@name='ctl00$ContentPlaceHolder1$ddlAno']"]];
	XMLElement *periodSelect = [document firstElementMatchingPath:[m3tPath stringByAppendingString:@"/select[@name='ctl00$ContentPlaceHolder1$ddlEtapa']"]];
	
	/*NSArray *yearOptionElements = [yearSelect elementsMatchingPath:@"./option"];
	for (XMLElement *element in yearOptionElements) {
		Pair *p = [[[Pair alloc] initWithObjects:[element content], [[element attributes] objectForKey:@"value"]] autorelease];
		[$yearOptions addObject:p];
	}*/
	// Unfortunately, it's impossible to attempt any debugging with the server at its current state.
	// Maybe next year.
	Pair *pa = [[[Pair alloc] initWithObjects:@"2013", @"2013"] autorelease];
	[$yearOptions addObject:pa];
	
	if ([$yearOptions count] == 0) {
		[self displayFailViewWithImage:nil text:@"Falha ao interpretar página (notasparciais.aspx:Select)\n\nEstamos trabalhando para consertar este problema."];
		return;
	}

	for (Pair *year in $yearOptions) {
		NSArray *periodOptionElements = [periodSelect elementsMatchingPath:@"./option"];
		NSMutableArray *periods = [NSMutableArray array];
		for (XMLElement *element in periodOptionElements) {
			Pair *p = [[[Pair alloc] initWithObjects:[[element content] stringByAppendingString:@" Período"], [[element attributes] objectForKey:@"value"]] autorelease];
			[periods addObject:p];
		}
		[$periodOptions setObject:periods forKey:year->obj2];
	}
	
	[document release];

	
	NSLog(@"%@ %@", $yearOptions, $periodOptions);
	
	[self $performUIBlock:^{
		UITableView *tableView = (UITableView *)[self contentView];
		[tableView reloadData];

		[self displayContentView];
	}];
}

- (void)loadContentView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:FixViewBounds([[self view] bounds]) style:UITableViewStylePlain];
	[tableView setDelegate:self];
	[tableView setDataSource:self];

	$contentView = tableView;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [$yearOptions count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	Pair *yearValue_ = [$yearOptions objectAtIndex:section];
	NSString *yearValue = yearValue_->obj2;
	return [[$periodOptions objectForKey:yearValue] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PortoAppGradeViewControllerCell"];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PortoAppGradeViewControllerCell"] autorelease];
	}
	
	Pair *yearValue_ = [$yearOptions objectAtIndex:[indexPath section]];
	NSString *yearValue = yearValue_->obj2;
	Pair *pair = [[$periodOptions objectForKey:yearValue] objectAtIndex:[indexPath row]];
	[[cell textLabel] setText:(NSString *)pair->obj1];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	Pair *yearValue_ = [$yearOptions objectAtIndex:[indexPath section]];
	NSString *yearValue = yearValue_->obj2;
	Pair *periodValue_ = [[$periodOptions objectForKey:yearValue] objectAtIndex:[indexPath row]];
	NSString *periodValue = periodValue_->obj2;

	GradesListViewController *listController = [[[GradesListViewController alloc] initWithYear:yearValue period:periodValue viewState:$viewState eventValidation:$eventValidation] autorelease];
	[[self navigationController] pushViewController:listController animated:YES];

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	Pair *year = [$yearOptions objectAtIndex:section];
	return year->obj1;
}

- (void)freeData {
	//[$gradeDump release];
	[super freeData];
}

- (void)dealloc {
	[$yearOptions release];
	[$periodOptions release];
	[$viewState release];
	[$eventValidation release];

	[super dealloc];
}
@end

/* }}} */

/* Papers Controller {{{ */

@implementation PapersViewController
- (id)initWithIdentifier:(NSString *)identifier {
	if ((self = [super initWithIdentifier:identifier])) {
		$viewState = NULL;
		$folder = NULL;
	}

	return self;
}

- (void)reloadData {
	[super reloadData];
	
	if ($folder == NULL) {
		[self setTitle:@"Circulares"];
		
		SessionController *sessionController = [SessionController sharedInstance];
		if (![sessionController hasSession]) [self displayFailViewWithImage:nil text:@"Sem autenticação.\nRealize um login no menu de Contas."];
		if (![sessionController papersID]) {
                        NSLog(@"err id");
			[self displayFailViewWithImage:nil text:@"Falha ao obter o ID de Circulares.\n\nEstamos trabalhando para consertar este problema."];
			return;
		}

		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?token=%@", kPortoRootCircularesPage, [sessionController papersID]]];
		NSURLResponse *response;
		NSData *data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:NULL];
		if (data == nil) {
                        NSLog(@"err intern");
			[self displayFailViewWithImage:nil text:@"Falha ao carregar página.\n\nCheque sua conexão de Internet."];
			return;
		}

		XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
		//NSLog(@"FORM CONTENT %@", [[document firstElementMatchingPath:@"/html/body/form"] content]);
		//NSLog(@"also got %@", [document firstElementMatchingPath:@"/html/body/form/div"]);
		XMLElement *viewStateInput = [document firstElementMatchingPath:@"/html/body/form/input[@id='__VIEWSTATE']"];
		NSLog(@"EL %@", viewStateInput);
		NSLog(@"GOT %@ %@", [viewStateInput tagName], [[viewStateInput attributes] objectForKey:@"id"]);
		
		NSString *value = [[viewStateInput attributes] objectForKey:@"value"];
		char *str = (char *)malloc([value length] * sizeof(char));
		
		int blen = base64_decode([value UTF8String], [value length], &str);
		if (blen < 0) {
			NSLog(@"err blen");
                        [self displayFailViewWithImage:nil text:@"Erro interpretando página.\nEstamos trabalhando no problema.\n\n(Base64)"];
			return;
		}
		
		$viewState = parse_viewstate((unsigned char **)&str, true);
		if ($viewState->stateType == kViewStateTypeError) {
			NSLog(@"err vs");
                        [self displayFailViewWithImage:nil text:@"Erro interpretando página.\nEstamos trabalhando no problema.\n\n(ViewState)"];
			return;
		}
		
		$folder = $viewState->pair->first->pair->second->pair->second->arrayList[1]->pair->second->arrayList[5]->pair->first->array->array[1]->array->array[1]->array->array[1];
                NSLog(@"$folder ptr %p", $folder);
		[document release];
	}
        
        [self $performUIBlock:^{
                UITableView *tableView = (UITableView *)[self contentView];
                [tableView reloadData];
                
                NSLog(@"DISPLAY CONTENT VIEW!!");
                [self displayContentView];
        }];
}

- (void)loadContentView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:FixViewBounds([[self view] bounds]) style:UITableViewStylePlain];
	[tableView setDelegate:self];
	[tableView setDataSource:self];

	$contentView = tableView;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
        return $folder == NULL ? 0 : $folder->array->length-1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PortoAppCirculares"];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PortoAppCirculares"] autorelease];
		
		UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedScrollView:)];
		UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(15.f, [cell bounds].origin.y, [cell bounds].size.width - 15.f, [cell bounds].size.height)];
		[scrollView setBackgroundColor:[UIColor whiteColor]];
		[scrollView addGestureRecognizer:tapGestureRecognizer];
		[tapGestureRecognizer release];
		//[scrollView setBounces:NO];

		UILabel *label = [[UILabel alloc] initWithFrame:[cell bounds]];
		[label setTextColor:[UIColor blackColor]];
		[label setBackgroundColor:[UIColor clearColor]];
		[label setFont:[[cell textLabel] font]];
		[label setTag:88];
		[scrollView addSubview:label];
		[label release];

		[scrollView setTag:87];
		[[cell contentView] addSubview:scrollView];
		[scrollView release];
	}
	
	vsType *subType = $folder->array->array[[indexPath row]+1];
	BOOL isFolder = subType->array->array[1]->stateType != kViewStateTypeNull;

        NSString *text = [NSString stringWithUTF8String:subType->array->array[0]->arrayList[1]->string];
	if (!isFolder && ![text hasPrefix:@"<a"]) {
		isFolder = YES;
	}
	
	NSString *endText = isFolder ? text : GetATagContent(text);
	//[[cell textLabel] setText:isFolder ? text : GetATagContent(text)];
        [cell setAccessoryType:isFolder ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone];
	
	UIScrollView *scrollView = (UIScrollView *)[cell viewWithTag:87];
	UILabel *label = (UILabel *)[scrollView viewWithTag:88];
	CGFloat width = [endText sizeWithFont:[label font]].width;
	
	[scrollView setFrame:(CGRect){[scrollView frame].origin, {isFolder ? [scrollView frame].size.width-15.f : [scrollView frame].size.width, [scrollView frame].size.height}}];
	[scrollView setContentSize:CGSizeMake(width < [scrollView bounds].size.width ? [scrollView bounds].size.width : width, [scrollView contentSize].height)];
	
	[label setFrame:(CGRect){[label frame].origin, {[scrollView contentSize].width, [label frame].size.height}}];
	[label setText:endText];

	return cell;
}

- (void)$setFolder:(vsType *)folder {
	[self setTitle:[NSString stringWithUTF8String:folder->array->array[0]->arrayList[1]->string]];
        
        if (folder->array->array[1]->stateType != kViewStateTypeNull)
                $folder = folder->array->array[1];
        else
                $folder = folder;
}

- (void)tappedScrollView:(UIGestureRecognizer *)rec {
	UITableView *tableView = (UITableView *)$contentView;
	NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:[rec locationInView:tableView]];
	
	[tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionMiddle];
	[self tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	vsType *subType = $folder->array->array[[indexPath row]+1];
        
	if (subType->array->array[1]->stateType != kViewStateTypeNull) {
                PapersViewController *controller = [[[PapersViewController alloc] initWithIdentifier:@"papers"] autorelease];
		[controller $setFolder:subType];

		[[self navigationController] pushViewController:controller animated:YES];
	}
	
	else {
		NSString *string = [NSString stringWithUTF8String:subType->array->array[0]->arrayList[1]->string];
		if (![string hasPrefix:@"<a"]) {
			UIAlertView *alertView = [[UIAlertView alloc] init];
			[alertView setTitle:@"Pasta vazia"];
			[alertView setMessage:@"Não há nenhuma circular nesta pasta."];
			[alertView setDelegate:nil];
			[alertView addButtonWithTitle:@"OK"];

			[alertView show];
			[alertView release];

			return;
		}

		NSString *title = GetATagContent(string);
		NSString *pdfAddress = [kPortoRootCircularesPage stringByAppendingString:GetATagHref(string)];
		
		WebViewController *webViewController = [[[WebViewController alloc] init] autorelease];
		[webViewController loadPage:[pdfAddress stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

		[webViewController setTitle:title];
		[[self navigationController] pushViewController:webViewController animated:YES];
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)freeData {
	[super freeData];
}

- (void)dealloc {
	/*if ($viewState != NULL)
		free_viewstate($viewState);*/
	[super dealloc];
}
@end

/* }}} */

/* Services Controller {{{ */

@implementation ServicesViewController
- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor blueColor]];
}
@end

/* }}} */

/* Account Controller {{{ */

@implementation AccountViewController
- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor blueColor]];
}

- (void)popupLoginController {
	PortoLoginController *loginController = [[PortoLoginController alloc] init];
	[loginController setDelegate:self];
	UINavigationController *navLoginController = [[[UINavigationController alloc] initWithRootViewController:loginController] autorelease];
	[self presentViewController:navLoginController animated:YES completion:NULL];
	[loginController release];
}

- (void)loginControllerDidLogin:(LoginController *)controller {
	NSLog(@"DID LOGIN.");
	[self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)loginControllerDidCancel:(LoginController *)controller {
	[self dismissViewControllerAnimated:YES completion:NULL];
}
@end

/* }}} */

static void DebugInit() {
	//[[SessionController sharedInstance] setAccountInfo:nil];
}

/* App Delegate {{{ */

@implementation AppDelegate
@synthesize window = $window;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
	DebugInit();
	
	$window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	
	NewsViewController *newsViewController = [[[NewsViewController alloc] init] autorelease];
	UINavigationController *newsNavController = [[[UINavigationController alloc] initWithRootViewController:newsViewController] autorelease];
	[newsNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notícias" image:nil tag:0] autorelease]];
	
	GradesViewController *gradesViewController = [[[GradesViewController alloc] initWithIdentifier:@"grades"] autorelease];
	UINavigationController *gradesNavController = [[[UINavigationController alloc] initWithRootViewController:gradesViewController] autorelease];
	[gradesNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notas" image:nil tag:0] autorelease]];
	
	PapersViewController *papersViewController = [[[PapersViewController alloc] initWithIdentifier:@"papers"] autorelease];
	UINavigationController *papersNavController = [[[UINavigationController alloc] initWithRootViewController:papersViewController] autorelease];
	[papersNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Circulares" image:nil tag:0] autorelease]];

	ServicesViewController *servicesViewController = [[[ServicesViewController alloc] init] autorelease];
	[servicesViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Serviços" image:nil tag:0] autorelease]];

	AccountViewController *accountViewController = [[[AccountViewController alloc] init] autorelease];
	UINavigationController *accountNavViewController = [[[UINavigationController alloc] initWithRootViewController:accountViewController] autorelease];
	[accountNavViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Conta" image:nil tag:0] autorelease]];

	NSArray *controllers = [NSArray arrayWithObjects:
		newsNavController,
		gradesNavController,
		papersNavController,
		servicesViewController,
		accountNavViewController,
		nil];
	$tabBarController = [[UITabBarController alloc] init];
	[$tabBarController setViewControllers:controllers];

	[[UINavigationBar appearance] setTintColor:UIColorFromHexWithAlpha(0x1c2956, 1.f)];

	[$window setRootViewController:$tabBarController];
	[$window makeKeyAndVisible];
	
	[[SessionController sharedInstance] loadSessionWithHandler:^(BOOL success, NSError *error){
		if (success) return;

		if ([[error domain] isEqualToString:kPortoErrorDomain]) {
			if ([error code] == 10) {
				NSLog(@"HI");
				[$tabBarController setSelectedIndex:4];
				[accountViewController popupLoginController];
				NSLog(@"BYE");
			}

			else {
				UIAlertView *errorAlert = [[UIAlertView alloc] init];
				[errorAlert setTitle:@"Erro"];
				[errorAlert setMessage:[NSString stringWithFormat:@"Erro de conexão (%d).", [error code]]];
				[errorAlert addButtonWithTitle:@"OK"];
				[errorAlert setCancelButtonIndex:0];
				[errorAlert show];
				[errorAlert release];
			}
		}
		else {
			UIAlertView *errorAlert = [[UIAlertView alloc] init];
			[errorAlert setTitle:@"Erro"];
			[errorAlert setMessage:[NSString stringWithFormat:@"Erro desconhecido (%@: %d).", [error domain], [error code]]];
			[errorAlert addButtonWithTitle:@"OK"];
			[errorAlert setCancelButtonIndex:0];
			[errorAlert show];
			[errorAlert release];
		}
	}];

	NSLog(@"End App Delegate init.");
}

- (void)dealloc {
	[$window release];
	[$tabBarController release];
	
	[super dealloc];
}
@end

/* }}} */

/* Main {{{ */

int main(int argc, char **argv) {
	debug(@"Entering main()");
	
	InitCache();

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int ret = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    
	[pool drain];
	return ret;
}

/* }}} */

/* }}} */
