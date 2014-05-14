/* PortoApp
 iOS interface to the Colégio Visconde de Porto Seguro grade/news etc.
 
 Created by Daniel Ferreira in 9/09/2013
 (c) 2013 Daniel Ferreira
 no rights whatsoever to the Fundação Visconde de Porto Seguro
 
 The source code and copies built with it and binaries shipped with this source distribution are licensed under the GNU General Public License version 3.
 The App Store copy has all rights reserved.
 */

// Tips:
// [23:41:33] <@DHowett> theiostream: At the top of the function, get 'self.bounds' out into a local variable. each time you call it is a dynamic dispatch because the compiler cannot assume that it has no side-effects

// Global TODOs:
// IMPLEMENT PRETTY SOON: URL Request Caching better handling
// IMPLEMENT PRETTY SOON: Better handling of the fuckshit view controller view bounds thing
// IMPLEMENT PRETTY SOON [23:42:13] <@DHowett> theiostream: the attributed strings and their CTFrameshit should be cached whenver possible. do not create a new attributed string every time the rect is drawn
// IMPLEMENT PRETTY SOON: Push Notifications
// IMPLEMENT PRETTY SOON: Learn NSURLSession (iOS7+, but regardless... we can do two branches for certain moment and afterwards implement compatibility measures.

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
#import <SystemConfiguration/SystemConfiguration.h>

#include <dlfcn.h>

#include "viewstate/viewstate.h"
/* }}} */

/* External {{{ */

#import "External.mm"

static UIImage *(*_UIImageWithName)(NSString *);

typedef enum : NSInteger {
	NotReachable = 0,
	ReachableViaWiFi,
	ReachableViaWWAN
} NetworkStatus;

/* }}} */

/* Macros {{{ */

#define SYSTEM_VERSION_GT_EQ(v) \
	([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

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

#define LOG_ALLOC(ptr) \
	NSLog(@"%p: ALLOC (%d)", ptr, [ptr retainCount]);
#define LOG_RETAIN(ptr) \
	NSLog(@"%p: RETAI (%d)", ptr, [ptr retainCount]);
#define LOG_RELEASE(ptr) \
	NSLog(@"%p: RELES (%d)", ptr, [ptr retainCount]);

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

static NSString *NSDictionaryURLEncode(NSDictionary *dict) {
	NSMutableString *ret = [NSMutableString string];
	
	NSArray *allKeys = [dict allKeys];
	for (NSString *key in allKeys) {
		[ret appendString:NSStringURLEncode(key)];
		[ret appendString:@"="];
		[ret appendString:NSStringURLEncode([dict objectForKey:key])];
		[ret appendString:@"&"];
	}
	
	return [ret substringToIndex:[ret length]-1];
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
	return CGRectMake(bounds.origin.x, (HEIGHT_OF_STATUSBAR + HEIGHT_OF_NAVBAR)*2, bounds.size.width, bounds.size.height - HEIGHT_OF_STATUSBAR - HEIGHT_OF_NAVBAR - HEIGHT_OF_TABBAR + 1.f);
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

/* Alert {{{ */

static void AlertError(NSString *title, NSString *text) {
	UIAlertView *alertView = [[UIAlertView alloc] init];
	[alertView setTitle:title];
	[alertView setMessage:text];
	[alertView addButtonWithTitle:@"OK"];
	[alertView setDelegate:nil];
	
	[alertView show];
	[alertView release];
}

/* }}} */

/* Derp Cipher {{{ */

static char *decode_derpcipher(const char *str) {
	char *r = (char *)malloc((strlen(str) + 1) * sizeof(char));
	int i, len=strlen(str);
        
	for (i=0; i<len; i++) { r[i] = str[i]-1; }
	r[i] = '\0';
	
	return r;
}

/* }}} */

/* }}} */

/* Constants {{{ */

#define kReportIssue "\n\nPara averiguarmos o problema, mande um email para q@theiostream.com descrevendo o erro."
#define kServerError "\n\nTente recarregar a página ou espere o site se recuperar de algum problema."

#define kMissingGradesBacktraceStackTop @"notasParciaisWeb.NotasParciais.carregaPagina(String matricula) in D:\\Projetos\\Notas_Parciais\\notasParciaisWeb\\NotasParciais.aspx.cs:148"
#define kNoGradesLabelText @"Nenhuma avaliação ou nota encontrada para o aluno"
#define kNoZeugnisMessage @"O Boletim não pode ser visualizado no momento."

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
	KeychainItemWrapper *$truyyutItem;

	NSDictionary *$accountInfo;
	NSString *$gradeID;
	NSString *$papersID;
	NSString *$truyyut;
	
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

- (NSString *)truyyut;
- (void)setTruyyut:(NSString *)truyyut;

- (NSDictionary *)sessionInfo;
- (void)setSessionInfo:(NSDictionary *)sessionInfo;
- (BOOL)hasSession;

- (void)loadSessionWithHandler:(void(^)(BOOL, NSError *))handler;
- (void)unloadSession;

- (NSArray *)authenticationCookies;

- (NSURLRequest *)requestForPageWithURL:(NSURL *)url method:(NSString *)method cookies:(NSArray *)cookies;
- (NSURLRequest *)requestForPageWithURL:(NSURL *)url method:(NSString *)method;
- (NSData *)loadPageWithURL:(NSURL *)url method:(NSString *)method response:(NSURLResponse **)response error:(NSError **)error;
@end

/* }}} */

/* Views {{{ */

/* Recovery View {{{ */

@class GradeContainer;

@protocol RecoveryTableViewCellDelegate;
@interface RecoveryTableViewCell : ABTableViewCell {
	UISlider *$slider;
}

@property (nonatomic, assign) id<RecoveryTableViewCellDelegate> delegate;
@property (nonatomic, retain) GradeContainer *container;
@property (nonatomic, retain) GradeContainer *backupContainer;

@property (nonatomic, retain) NSString *rightText;
@property (nonatomic, retain) NSString *topText;
@property (nonatomic, retain) NSString *bottomText;

- (UISlider *)slider;
@end

@protocol RecoveryTableViewCellDelegate <NSObject>
- (void)sliderValueChangedForRecoveryCell:(RecoveryTableViewCell *)cell;
@end

/* }}} */

/* Pie Chart View {{{ */

@class GradeContainer;
@class PieChartView;

// i don't like iOS 7
@interface PickerActionSheet : UIView <UIPickerViewDelegate, UIPickerViewDataSource> {
	UILabel *$subtitleLabel;
	
	NSInteger *$rowMap;
	NSInteger $selectedContainerType;
}
@property(nonatomic, assign) PieChartView *delegate;

- (id)initWithHeight:(CGFloat)height;
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
@interface PieChartView : UIView <PieChartSliderViewDelegate> {
	PieChartPiece *$emptyPiece;
	NSMutableArray *$pieces;
	CGFloat $radius;

	NSInteger $percentageSum;
	
	UIButton *$addGradeButton;
}
@property(nonatomic, assign) id<PieChartViewDelegate> delegate;
+ (CGFloat)extraHeight;
- (id)initWithFrame:(CGRect)frame pieces:(NSArray *)pieces count:(NSUInteger)count radius:(CGFloat)radius emptyPiece:(PieChartPiece *)empty;
- (void)updateBonusSliders;
- (void)didClosePickerSheet:(PickerActionSheet *)$pickerSheet withRowMap:(NSInteger *)$rowMap selectedContainerType:(NSInteger)$selectedContainerType;
- (void)didCancelPickerSheet:(PickerActionSheet *)pickerSheet;
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
	UILabel *label;
	UILabel *titleLabel;
}
@property(nonatomic, retain) NSString *text;
@property(nonatomic, retain) NSString *title;
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
	UIView *$cacheView;

	UIBarButtonItem *$refreshButton;
	UIBarButtonItem *$spinnerButton;

	NSData *$cachedData;
	NSString *$cacheIdentifier;
}

- (WebDataViewController *)initWithIdentifier:(NSString *)identifier;
- (CGRect)contentViewFrame;

- (UIView *)contentView;
- (void)loadContentView;
- (void)unloadContentView;

- (void)refresh;
- (void)reloadData;

- (void)$freeViews;
- (void)freeData;

- (void)displayLoadingView;
- (void)hideLoadingView;
- (void)displayFailViewWithTitle:(NSString *)title text:(NSString *)text;
- (void)displayContentView;

- (void)$performUIBlock:(void(^)())block;

- (BOOL)shouldUseCachedData;
- (NSData *)cachedData;
- (void)cacheData:(NSData *)data;
@end
#define IfNotCached { if(![self shouldUseCachedData])
#define ElseNotCached(x) else{ x = [self cachedData]; } }

/* }}} */

/* Web View Controller {{{ */

@interface WebViewController : UIViewController <UIWebViewDelegate> {
	UIWebView *$webView;
	FailView *$failView;
	LoadingIndicatorView *$loadingView;

	UIBarButtonItem *$refreshButton;
	UIBarButtonItem *$spinnerButton;
}
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

@interface NewsArticleWebViewController : WebViewController {
	dispatch_queue_t $queue;
	NSURL *$newsURL;
}
- (id)initWithQueue:(dispatch_queue_t)queue newsURL:(NSURL *)newsURL;
@end

@interface NavigationWebBrowserController : WebViewController {
	dispatch_queue_t $queue;
}

- (id)initWithQueue:(dispatch_queue_t)queue;
@end

@interface NewsTableViewCell : ABTableViewCell {
        UIImage *$newsImage;
        NSString *$newsTitle;
        NSString *$newsSubtitle;
	
	UIImageView *$imageView;
}

@property(nonatomic, retain) UIImage *newsImage;
@property(nonatomic, retain) NSString *newsTitle;
@property(nonatomic, retain) NSString *newsSubtitle;
@end

@interface NewsViewController : WebDataViewController <UITableViewDelegate, UITableViewDataSource> {
	NSMutableArray *$imageData;
}
@end

/* }}} */

/* Grades {{{ */

#define kPortoAverage 60

@interface GradeContainer : NSObject <NSCopying>
@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSString *grade;
@property(nonatomic, retain) NSString *value;
@property(nonatomic, retain) NSString *average;
@property(nonatomic, assign) NSInteger weight;

@property(nonatomic, retain) NSMutableArray *subGradeContainers;
@property(nonatomic, retain) NSMutableArray *subBonusContainers;
@property(nonatomic, assign) GradeContainer *superContainer;

@property(nonatomic, assign) BOOL isBonus;
@property(nonatomic, assign) NSUInteger section;

@property(nonatomic, assign) BOOL showsGraph;
@property(nonatomic, assign) BOOL isRecovery;

- (NSInteger)totalWeight;
- (BOOL)isAboveAverage;

- (void)makeValueTen;

- (NSString *)gradePercentage;
- (void)calculateGradeFromSubgrades;
- (void)calculateAverageFromSubgrades;
- (NSInteger)indexAtSupercontainer;
- (float)gradeInSupercontainer;
- (float)$gradePercentage;

- (BOOL)hasGrade;
- (BOOL)hasAverage;

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

@interface SubjectView : UICollectionViewCell <UITableViewDataSource, UITableViewDelegate, PieChartViewDelegate> {
	GradeContainer *$container;
	NoButtonDelayTableView *$tableView;
	UILabel *nameLabel;
}
@property (nonatomic, retain) GradeContainer *container;

- (id)initWithFrame:(CGRect)frame;
@end

@interface GradesSubjectView : SubjectView
@end

@interface GradesListViewController : WebDataViewController <UICollectionViewDataSource, UICollectionViewDelegate> {
	NSString *$year;
	NSString *$period;
	NSString *$viewState;
	NSString *$eventValidation;

	GradeContainer *$rootContainer;
}

- (GradesListViewController *)initWithYear:(NSString *)year period:(NSString *)period viewState:(NSString *)viewState eventValidation:(NSString *)eventValidation;
@property (nonatomic, retain) NSString *year;
@property (nonatomic, retain) NSString *period;
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

@protocol Service <NSObject>
@required
- (NSString *)serviceName;
@end

@interface ZeugnisSubjectView : SubjectView <RecoveryTableViewCellDelegate>
@end

@interface ZeugnisListViewController : WebDataViewController <UICollectionViewDataSource, UICollectionViewDelegate> {
	NSDictionary *$postKeys;
	NSArray *$cookies;
	
	GradeContainer *$rootContainer;
}

- (id)initWithIdentifier:(NSString *)identifier cacheIdentifier:(NSString *)cacheIdentifier postKeys:(NSDictionary *)dict cookies:(NSArray *)cookies;
@end

@interface ZeugnisViewController : WebDataViewController <Service, UITableViewDataSource, UITableViewDelegate> {
	NSMutableArray *$yearOptions;
	
	NSString *$viewState;
	NSString *$eventValidation;
	NSArray *$cookies;
}
@end

@interface ClassViewController : WebDataViewController <Service> {
	UILabel *$yearLabel;
	UILabel *$classLabel;
}
@end

@interface PhotoViewController : WebDataViewController <Service>
@end

@interface ServicesViewController : UITableViewController <UIAlertViewDelegate, UITextFieldDelegate> {
	NSArray *$controllers;
	NSMutableArray *$customLinks;
}
@end

/* }}} */

/* Account {{{ */

@interface AccountViewController : UITableViewController <LoginControllerDelegate> {
	UIView *$infoView;
	
	UITableViewCell *$loginOutCell;
	UITableViewCell *$aboutCell;
	UITableViewCell *$theiostreamCell;

	SCNetworkReachabilityRef $reachability;

@public
	BOOL $isLoggingIn;	
}
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
        [label_ setText:@"Carregando..."];
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
@synthesize text, title;

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		[self setBackgroundColor:[UIColor whiteColor]];
		
		centerView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, [[UIScreen mainScreen] bounds].size.width, 0.f)];
		
		titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		[titleLabel setFont:[UIFont fontWithName:@"HelveticaNeue" size:18.f]];
		[titleLabel setTextAlignment:NSTextAlignmentCenter];
		[titleLabel setTextColor:[UIColor lightGrayColor]];
		[titleLabel setNumberOfLines:0];
		[centerView addSubview:titleLabel];
		[titleLabel release];
		
		label = [[UILabel alloc] initWithFrame:CGRectZero];
		[label setFont:[UIFont fontWithName:@"HelveticaNeue" size:13.f]];
		[label setTextAlignment:NSTextAlignmentCenter];
		[label setTextColor:[UIColor lightGrayColor]];
		[label setNumberOfLines:0];
		[centerView addSubview:label];
		[label release];

		[self addSubview:centerView];
		[centerView release];
	}

	return self;
}

- (void)setTitle:(NSString *)title_ {
	NSLog(@"SET TITLE FOR VIEW %p %@", self, title_);
	title = [title_ retain];
	[titleLabel setText:title];
}

- (void)setText:(NSString *)text_ {
	NSLog(@"SET TEXT FOR VIEW %p %@", self, text_);
        text = [text_ retain];
	[label setText:text];
}

- (void)layoutSubviews {
	[super layoutSubviews];
    	
	CGSize titleSize = [title sizeWithFont:[UIFont fontWithName:@"HelveticaNeue" size:18.f] constrainedToSize:CGSizeMake([self bounds].size.width, CGFLOAT_MAX)/* lineBreakMode:NSLineBreakByWordWrapping*/];
        CGSize textSize = [text sizeWithFont:[UIFont fontWithName:@"HelveticaNeue" size:13.f] constrainedToSize:CGSizeMake([self bounds].size.width, CGFLOAT_MAX)/* lineBreakMode:NSLineBreakByWordWrapping*/];
        
        CGFloat sumHeight = titleSize.height + textSize.height + 15.f;
        [centerView setFrame:CGRectMake([centerView frame].origin.x, [self bounds].size.height/2 - sumHeight/2, [centerView frame].size.width, sumHeight)];
        
	[titleLabel setFrame:CGRectMake(0.f, 0.f, [self bounds].size.width, titleSize.height)];
	[label setFrame:CGRectMake(0.f, [centerView bounds].size.height - textSize.height, [self bounds].size.width, textSize.height)];
	NSLog(@"FRAMES %@ %@", NSStringFromCGRect([titleLabel frame]), NSStringFromCGRect([label frame]));

	/*[titleLabel sizeToFit];
	[titleLabel setFrame:CGRectMake(0.f, 0.f, [titleLabel frame].size.width, titleSize.height)];
	[titleLabel setCenter:CGPointMake([centerView center].x, [titleLabel center].y)];
	
	[label sizeToFit];
	[label setFrame:CGRectMake(0.f, [centerView bounds].size.height - textSize.height, [label frame].size.width, textSize.height)];
	[label setCenter:CGPointMake([centerView center].x, [label center].y)];*/
}

- (void)dealloc {
	[text release];
	[title release];

	[super dealloc];
}
@end

/* }}} */

/* Pie Chart View {{{ */

// FIXME: Don't have repeated views. Maybe reuse at least the PickerActionSheet?
#define kPickerActionSheetSpaceAboveBottom 5.f
@implementation PickerActionSheet
@synthesize delegate;

- (id)initWithHeight:(CGFloat)height {
        UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
        if ((self = [super initWithFrame:CGRectMake(5.f, [keyWindow bounds].size.height, [keyWindow bounds].size.width - 10.f, height)])) {
		$rowMap = (NSInteger *)calloc(2, sizeof(NSInteger));
		$selectedContainerType = 0;

		[self setBackgroundColor:[UIColor whiteColor]];
		[[self layer] setMasksToBounds:NO];
		[[self layer] setCornerRadius:8];

		UIPickerView *pickerView = [[UIPickerView alloc] initWithFrame:CGRectMake(0.f, HEIGHT_OF_NAVBAR, [self bounds].size.width, height - HEIGHT_OF_NAVBAR)];
		[pickerView setDelegate:self];
		[pickerView setDataSource:self];
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
		[doneButton addTarget:self action:@selector(doneWithPickerView:) forControlEvents:UIControlEventValueChanged];
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
	}

	return self;
}

- (void)setSubtitleLabelText:(NSString *)text {
	[$subtitleLabel setText:text];
}

- (void)display {
	[[[UIApplication sharedApplication] keyWindow] addSubview:self];

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

- (void)$dismiss:(id)sender { [[self delegate] didCancelPickerSheet:self]; }
- (void)dismiss {
	UIView *endarkenView = [[[UIApplication sharedApplication] keyWindow] viewWithTag:66];
	
	[UIView animateWithDuration:.5f animations:^{
		[self setFrame:CGRectMake([self frame].origin.x, [self frame].origin.y + kPickerActionSheetSpaceAboveBottom + [self frame].size.height, [self frame].size.width, [self frame].size.height)];
		[endarkenView setAlpha:0.f];
	} completion:^(BOOL finished){
		[endarkenView removeFromSuperview];
		[self removeFromSuperview];
	}];
}

- (void)dealloc {
	[$subtitleLabel release];
	free($rowMap);

	[super dealloc];
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

		[self setSubtitleLabelText:[@"Selecione o " stringByAppendingString:row==0 ? @"peso." : @"valor."]];
	}
	else $rowMap[$selectedContainerType] = row;
}

- (void)doneWithPickerView:(UISegmentedControl *)sender {
	$rowMap[0] = 0;
	$rowMap[1] = 0;
	$selectedContainerType = 0;

	[[self delegate] didClosePickerSheet:self withRowMap:$rowMap selectedContainerType:$selectedContainerType];
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
		/*UIImage *knobImage = UIImageResize([UIImage imageNamed:@"UISliderHandle.png"], CGSizeMake(15.f, 15.f));
		UIImage *knobPressedImage = UIImageResize([UIImage imageNamed:@"UISliderHandleDown.png"], CGSizeMake(15.f, 15.f));*/
		UIImage *knobImage = UIImageResize(_UIImageWithName(@"UISliderHandle.png"), CGSizeMake(15.f, 15.f));
		UIImage *knobPressedImage = UIImageResize(_UIImageWithName(@"UISliderHandleDown.png"), CGSizeMake(15.f, 15.f));

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
		if (!SYSTEM_VERSION_GT_EQ(@"7.0")) [[$addGradeButton titleLabel] setTextColor:UIColorFromHexWithAlpha(0x63B8FF, 1.f)];
		[$addGradeButton setTitle:@"Adicionar Nota" forState:UIControlStateNormal];
		[$addGradeButton setBackgroundColor:[UIColor clearColor]];
		[$addGradeButton setTitleColor:[$addGradeButton tintColor] forState:UIControlStateNormal];
		[$addGradeButton setTitleShadowColor:[UIColor blackColor] forState:UIControlStateHighlighted];
		[$addGradeButton addTarget:self action:@selector(thisIsACoolMethodButIAmSadIAlsoLoveCris:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:$addGradeButton];
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

- (void)thisIsACoolMethodButIAmSadIAlsoLoveCris:(UIButton *)button {
	PickerActionSheet *sheet = [[PickerActionSheet alloc] initWithHeight:260.f];
        [sheet setDelegate:self];
        [sheet display];
        [sheet release];
        
	[self setUserInteractionEnabled:NO];
	NSLog(@"SET NO USER INTERACTION ENABLED");
}

- (void)didClosePickerSheet:(PickerActionSheet *)$pickerSheet withRowMap:(NSInteger *)$rowMap selectedContainerType:(NSInteger)$selectedContainerType {
	[self setUserInteractionEnabled:YES];
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
}

- (void)didCancelPickerSheet:(PickerActionSheet *)pickerSheet {
	[self setUserInteractionEnabled:YES];
	[pickerSheet dismiss];
}

- (void)dealloc {
	[$emptyPiece release];
	[$pieces release];
	
	[$addGradeButton release];

	[super dealloc];
}
@end

/* }}} */

/* Grade Views {{{ */

// To be honest, I don't like this.
// We should use recursion. Recursive display of the tree, recursive building of the tree, etc.
// I doubt Porto will ever require/do such thing (due to their css class naming, I doubt their system support recursion),
// but I guess we should be better than them and implement this.
// Maybe a finish-up update before release?

// TODO: Make it impossible for Bonus Containers to call inappropriate methods 'by mistake'. Same for $NoGraders.
@implementation GradeContainer
@synthesize name, grade, value, average, subGradeContainers, subBonusContainers, weight, debugLevel, superContainer, isBonus, section, showsGraph, isRecovery;

- (id)init {
	if ((self = [super init])) {
		//LOG_ALLOC(self);
		debugLevel = 0;
		isBonus = NO;
		showsGraph = YES;
		isRecovery = NO;
	}

	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	GradeContainer *copy = [[[self class] alloc] init];
	[copy setName:[[self name] copy]];
	[copy setGrade:[[self grade] copy]];
	[copy setValue:[[self value] copy]];
	[copy setAverage:[[self average] copy]];
	[copy setSubGradeContainers:[[NSMutableArray alloc] initWithArray:[self subGradeContainers] copyItems:YES]];
	[copy setSubBonusContainers:[[NSMutableArray alloc] initWithArray:[self subBonusContainers] copyItems:YES]];
	[copy setWeight:[self weight]];
	[copy setDebugLevel:[self debugLevel]];
	[copy setSuperContainer:[self superContainer]];
	[copy setIsBonus:[self isBonus]];
	[copy setSection:[self section]];
	[copy setShowsGraph:[self showsGraph]];
	[copy setIsRecovery:[self isRecovery]];

	return copy;
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
	//[superContainer release];

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

- (BOOL)hasGrade {
	return ![[self grade] isEqualToString:@"$NoGrade"];
}

- (BOOL)hasAverage {
	return ![[self average] isEqualToString:@"$NoGrade"];
}

/*- (void)release {
	[super release];
        LOG_RELEASE(self);
}

- (id)retain {
	id r = [super retain];
        LOG_RETAIN(self);
        return r;
}*/
@end

// FIXME: Review ranges on both classes.
@implementation SubjectTableHeaderView
- (void)drawDataZoneRect:(CGRect)rect textColor:(CGColorRef)textColor dataFont:(CTFontRef)dataFont boldFont:(CTFontRef)boldFont inContext:(CGContextRef)context {
	CGFloat zoneWidth2 = rect.size.width/4;
	
	NSString *gradeString__ = ![[self container] hasGrade] ? @"N/A" : [[self container] grade];
	CFAttributedStringRef gradeString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Nota\n" stringByAppendingString:gradeString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange gradeContentRange = CFRangeMake(5, CFAttributedStringGetLength(gradeString_)-5);
	CFAttributedStringRef weightString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Peso\n" stringByAppendingString:[NSString stringWithFormat:@"%d", [[self container] weight]]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange weightContentRange = CFRangeMake(5, CFAttributedStringGetLength(weightString_)-5);
	NSString *averageString__ = ![[self container] hasAverage] ? @"N/A" : [[self container] average];
	CFAttributedStringRef averageString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Média\n" stringByAppendingString:averageString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange averageContentRange = CFRangeMake(5, CFAttributedStringGetLength(averageString_)-5);
	NSString *totalString__ = ![[self container] hasGrade] ? @"N/A" : [NSString stringWithFormat:@"%.2f", [[self container] gradeInSupercontainer]];
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
	
	NSString *gradeString__ = ![[self container] hasGrade] ? @"N/A" : [[self container] grade];
	CFAttributedStringRef gradeString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Nota\n" stringByAppendingString:gradeString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange gradeContentRange = CFRangeMake(5, CFAttributedStringGetLength(gradeString_)-5);
	CFAttributedStringRef valueString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Valor\n" stringByAppendingString:[[self container] value]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange valueContentRange = CFRangeMake(5, CFAttributedStringGetLength(valueString_)-5);
	NSString *percentString__ = ![[self container] hasGrade] ? @"N/A" : [[self container] gradePercentage];
	CFAttributedStringRef percentString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"%\n" stringByAppendingString:percentString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange percentContentRange = CFRangeMake(2, CFAttributedStringGetLength(percentString_)-2);
	NSString *averageString__ = ![[self container] hasAverage] ? @"N/A" : [[self container] average];
	CFAttributedStringRef averageString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Média\n" stringByAppendingString:averageString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange averageContentRange = CFRangeMake(5, CFAttributedStringGetLength(averageString_)-5);
	NSString *totalString__ = ![[self container] hasGrade] ? @"N/A" : [NSString stringWithFormat:@"%.2f", [[self container] gradeInSupercontainer]];
	CFAttributedStringRef totalString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Total\n" stringByAppendingString:totalString__], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
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
		while (![subjectView isKindOfClass:[GradesSubjectView class]]) subjectView = [subjectView superview];
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
	CGFloat zoneWidth = [container isBonus] || ![container showsGraph] ? rect.size.width/2 : rect.size.width/3;
	
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
	
	if ([container isBonus] || ![container showsGraph]) {
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
@synthesize container = $container;

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		$container = nil;

		[self setBackgroundColor:[UIColor whiteColor]];

		$tableView = [[NoButtonDelayTableView alloc] initWithFrame:[self bounds] style:UITableViewStylePlain];
		[$tableView setDataSource:self];
		[$tableView setDelegate:self];
		[$tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
		[$tableView setTag:77];
		[self addSubview:$tableView];
		
		// FIXME: Use CoreText instead of attributed UILabels.
		// (I'm asking myself why I did those in the first place.)
		UIView *tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, [$tableView bounds].size.width, 54.f)];
		CGFloat halfHeight = [tableHeaderView bounds].size.height/2;
		
		nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(5.f, 0.f, ([self bounds].size.width/3)*2, 54.f)];
		[nameLabel setBackgroundColor:[UIColor clearColor]];
		[nameLabel setTextColor:[UIColor blackColor]];
		[nameLabel setFont:[UIFont boldSystemFontOfSize:pxtopt(halfHeight)]];
		[nameLabel setNumberOfLines:0];
		[tableHeaderView addSubview:nameLabel];
		/*CGFloat width = [nameLabel bounds].size.width;
		[nameLabel sizeToFit];
		[nameLabel setFrame:CGRectMake(nameLabel.bounds.origin.x, nameLabel.bounds.origin.y, width, nameLabel.bounds.size.height)];*/

		/*if (![[container grade] isEqualToString:@"$NoGrade"]) {
			[self setupTableTopGradesWithTableHeaderView:tableHeaderView];
		}*/
		
		[$tableView setTableHeaderView:tableHeaderView];
		[tableHeaderView release];
		
		//[self setupTableFooterView];
	}

	return self;
}

- (void)setContainer:(GradeContainer *)container {
	if ($container) [$container release];
	$container = [container retain];
	
        [nameLabel setText:[container name]];
	[self setupTableFooterView];
	[self setupTableTopGradesWithTableHeaderView:[$tableView tableHeaderView]];

	[$tableView reloadData];
}

- (void)setupTableFooterView {
	return;
}

- (void)setupTableTopGradesWithTableHeaderView:(UIView *)tableHeaderView {
	return;
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
	BOOL notShowsGraph = !isBonus && ![[[$container subGradeContainers] objectAtIndex:section] showsGraph];

	NSString *identifier = isBonus ? @"PortoAppSubjectViewTableHeaderViewBonus" : @"PortoAppSubjectViewTableHeaderViewGrade";

	UITableViewHeaderFooterView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:identifier];
	if (headerView == nil) {
		headerView = [[[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:identifier] autorelease];

		UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0.f, 0.f, tableView.bounds.size.width, 44.f)];
		[scrollView setContentSize:CGSizeMake(scrollView.bounds.size.width * (isBonus || notShowsGraph ? 2 : 3), scrollView.bounds.size.height)];
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
	[$tableView release];
	[nameLabel release];
	[super dealloc];
}
@end

@implementation GradesSubjectView {
	UILabel *gradeLabel;
	UILabel *averageLabel;
}

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		CGRect nameLabelFrame = CGRectMake(5.f, 0.f, ([self bounds].size.width/3)*2, 54.f);
		
		gradeLabel = [[UILabel alloc] initWithFrame:CGRectMake(nameLabelFrame.size.width + 5.f, 0.f, [self bounds].size.width/3, 27.f)];
		[gradeLabel setBackgroundColor:[UIColor clearColor]];
		[gradeLabel setTextColor:[UIColor blackColor]];
		[[$tableView tableHeaderView] addSubview:gradeLabel];

		averageLabel = [[UILabel alloc] initWithFrame:CGRectMake(nameLabelFrame.size.width + 5.f, 22.f, [self bounds].size.width/3, 27.f)];
		[averageLabel setBackgroundColor:[UIColor clearColor]];
		[averageLabel setTextColor:[UIColor blackColor]];
		[[$tableView tableHeaderView] addSubview:averageLabel];
	}

	return self;
}

- (void)setupTableTopGradesWithTableHeaderView:(UIView *)tableHeaderView {
	NSString *gradeTitle = @"Nota: ";
	NSString *averageTitle = @"Média: ";

	NSMutableAttributedString *gradeAttributedString = [[NSMutableAttributedString alloc] initWithString:[gradeTitle stringByAppendingString:[$container grade]]];
	[gradeAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:pxtopt(24.f)] range:NSMakeRange(0, [gradeTitle length])];
	[gradeAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:pxtopt(24.f)] range:NSMakeRange([gradeTitle length], [gradeAttributedString length]-[gradeTitle length])];
	
	NSMutableAttributedString *averageAttributedString = [[NSMutableAttributedString alloc] initWithString:[averageTitle stringByAppendingString:[$container average]]];
	[averageAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:pxtopt(24.f)] range:NSMakeRange(0, [averageTitle length])];
	[averageAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:pxtopt(24.f)] range:NSMakeRange([averageTitle length], [averageAttributedString length]-[averageTitle length])];

	[gradeLabel setAttributedText:gradeAttributedString];
	[gradeAttributedString release];

	[averageLabel setAttributedText:averageAttributedString];
	[averageAttributedString release];
}

// URGENT FIXME self-explanatory
- (void)setupTableFooterView {
	UITableView *tableView = $tableView;
	
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

- (void)dealloc {
	[gradeLabel release];
	[averageLabel release];

	[super dealloc];
}
@end

/* }}} */

/* Recovery View {{{ */
// This whole thing, much like GradeContainer but a little worse, is completely undynamic.
// But unlike GradeContainer, there isn't much to be done here.

@implementation RecoveryTableViewCell
@synthesize delegate, container, backupContainer, rightText, topText, bottomText;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
	if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
		$slider = [[UISlider alloc] initWithFrame:CGRectZero];
		[$slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
		[self addSubview:$slider];
	}

	return self;
}

- (void)sliderChanged:(UISlider *)slider {
	[[self delegate] sliderValueChangedForRecoveryCell:self];
}

- (void)drawContentView:(CGRect)rect highlighted:(BOOL)highlighted {
	MAKE_CORETEXT_CONTEXT(context);
	
	UITableView *tableView = (UITableView *)self;
	while (![tableView isKindOfClass:[UITableView class]]) tableView = (UITableView *)[tableView superview];

	BOOL isOdd = [[tableView indexPathForCell:self] row] % 2 != 0;
	[(isOdd ? UIColorFromHexWithAlpha(0xfafafa, 1.f) : [UIColor whiteColor]) setFill];
	CGContextFillRect(context, rect);
	
	CGFloat div = 2;
	if ([self topText]) div++;
	if ([self bottomText]) div++;

	CGFloat zoneHeight = rect.size.height/2;
	CGFloat zoneWidth = rect.size.width;
	
	UIColor *colorForGrade = [[container grade] isEqualToString:@"$NoGrade"] ? UIColorFromHexWithAlpha(0x708090, 1.f) : ColorForGrade([container $gradePercentage]/10.f);
	[colorForGrade setFill];
	CGRect circleRect = CGRectMake(8.f, zoneHeight - zoneHeight/2.4, zoneHeight/1.2, zoneHeight/1.2);
	CGContextFillEllipseInRect(context, circleRect);
	
	CGColorRef textColor = [[UIColor blackColor] CGColor];

	NSString *systemFont = [[UIFont systemFontOfSize:1.f] fontName];
	CTFontRef dataFont = CTFontCreateWithName((CFStringRef)systemFont, pxtopt(18.f), NULL);
	CTFontRef boldFont = CTFontCreateCopyWithSymbolicTraits(dataFont, pxtopt(18.f), NULL, kCTFontBoldTrait, kCTFontBoldTrait);	

	if ([self rightText]) {
		CTFramesetterRef rightFramesetter = CreateFramesetter(boldFont, textColor, (CFStringRef)[self rightText], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
		DrawFramesetter(context, rightFramesetter, CGRectMake(zoneWidth - 48.f, rect.size.height/2 - 18.f, 48.f, 36.f));
		CFRelease(rightFramesetter);
	}
	if ([self topText]) {
		CTFramesetterRef rightFramesetter = CreateFramesetter(boldFont, textColor, (CFStringRef)[self topText], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
		DrawFramesetter(context, rightFramesetter, CGRectMake(0.f, [self bounds].size.height - 20.f, [self bounds].size.width, 18.f));
		CFRelease(rightFramesetter);
	}
	if ([self bottomText]) {
		CTFramesetterRef rightFramesetter = CreateFramesetter(dataFont, textColor, (CFStringRef)[self bottomText], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
		DrawFramesetter(context, rightFramesetter, CGRectMake(0.f, 2.f, [self bounds].size.width, 18.f));
		CFRelease(rightFramesetter);
	}
	
	CFRelease(dataFont);
	CFRelease(boldFont);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	[super touchesEnded:touches withEvent:event];
	
	if ([container isRecovery]) return;

	UITouch *touch = [touches anyObject];
	CGPoint location = [touch locationInView:self];
	if (CGRectContainsPoint(CGRectMake([self bounds].size.width - 48.f, 0.f, 48.f, [self bounds].size.height), location)) {
		[$slider setValue:[[backupContainer grade] floatValue]/10 animated:YES];
		[self sliderChanged:nil];
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat zoneHeight = [self bounds].size.height/2;
	[$slider setFrame:CGRectMake(10.f + zoneHeight, zoneHeight - 11, [self bounds].size.width - (10.f+zoneHeight) - 48.f, 23.f)];
}

- (void)setContainer:(GradeContainer *)container_ {
	container = [container_ retain];
	[$slider setValue:[container $gradePercentage]/100];
}

- (UISlider *)slider {
	return $slider;
}

- (void)dealloc {
	[$slider release];
	[container release];
	[backupContainer release];

	[super dealloc];
}
@end

/* }}} */

/* }}} */

/* Sessions {{{ */

/* Constants {{{ */

#define kPortoErrorDomain @"PortoServerError"

#define kPortoLoginURL @"http://www.educacional.com.br/login/login_ver.asp?URL="
#define kPortoLogoutURL @"http://www.educacional.com.br/login/logout.asp"

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
	$handler(nil, nil, [NSError errorWithDomain:@"PortoServerError" code:-2 userInfo:nil]);
	[self endConnection];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	$handler(nil, nil, [NSError errorWithDomain:kPortoErrorDomain code:-1 userInfo:nil]);
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
		/*$keychainItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoApp" accessGroup:@"am.theiostre.portoapp.keychain"];
		$gradeKeyItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppX" accessGroup:@"am.theiostre.portoapp.keychain"];
		$papersKeyItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppY" accessGroup:@"am.theiostre.portoapp.keychain"];
		$truyyutItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppZ" accessGroup:@"am.theiostre.portoapp.keychain"];*/
                $keychainItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoApp" accessGroup:nil];
                $gradeKeyItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppX" accessGroup:nil];
                $papersKeyItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppY" accessGroup:nil];
                $truyyutItem = [[KeychainItemWrapper alloc] initWithIdentifier:@"PortoAppZ" accessGroup:nil];

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
	NSLog(@"SET ACCOUNT INFO %@ FROM %@", accountInfo, [NSThread callStackSymbols]);

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

- (NSString *)truyyut {
	return $truyyut;
}

- (void)setTruyyut:(NSString *)truyyut {
	if ($truyyut != nil) [$truyyut release];

	if (truyyut == nil) [$truyyutItem resetKeychainItem];
	else {
		// FIXME: Same as above.
		[$truyyutItem setObject:@"bakon" forKey:(id)kSecAttrAccount];
		[$truyyutItem setObject:truyyut forKey:(id)kSecValueData];
	}

	$truyyut = [truyyut retain];
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

- (void)unloadSession {
	// FIXME: Implement a redirection system so I don't need to manually load all these URLs.
	// We don't care whether we managed to login or not -- after all, we're only doing this to spare Porto's servers from too many sections.
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		[self loadPageWithURL:[NSURL URLWithString:kPortoLogoutURL] method:@"GET" response:NULL error:NULL];
		[self loadPageWithURL:[NSURL URLWithString:@"http://pessoal.educacional.com.br/login/login_end.asp"] method:@"GET" response:NULL error:NULL];
		[self loadPageWithURL:[NSURL URLWithString:@"http://projetos.educacional.com.br/login/login_end.asp"] method:@"GET" response:NULL error:NULL];
		[self loadPageWithURL:[NSURL URLWithString:@"http://www.educacional.com.br/login/logout.asp?hl=ep"] method:@"GET" response:NULL error:NULL];
		[self loadPageWithURL:[NSURL URLWithString:@"http://portoseguro.educacional.net/include/esc_loginend.asp"] method:@"GET" response:NULL error:NULL];
	});

	[self setSessionInfo:nil];
}

- (NSArray *)authenticationCookies {
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

	return [NSArray arrayWithObjects:aspCookie, serverCookie, sessionCookie, nil];
}

- (NSURLRequest *)requestForPageWithURL:(NSURL *)url method:(NSString *)method cookies:(NSArray *)cookies {
	NSDictionary *headers = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
	NSLog(@"HEADERS %@", headers);

	NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
	[urlRequest setAllHTTPHeaderFields:headers];
	[urlRequest setHTTPMethod:method];
	
	if ([method isEqualToString:@"POST"]) {
		NSString *urlString = [url absoluteString];
		NSArray *parts = [urlString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"?"]];
		NSLog(@"parts are %@ AND %@", [parts objectAtIndex:0], [parts objectAtIndex:1]);
		[urlRequest setURL:[NSURL URLWithString:[parts objectAtIndex:0]]];
		[urlRequest setHTTPBody:[[parts objectAtIndex:1] dataUsingEncoding:NSUTF8StringEncoding]];
	}

	return urlRequest;
}

- (NSURLRequest *)requestForPageWithURL:(NSURL *)url method:(NSString *)method {
	return [self requestForPageWithURL:url method:method cookies:[self authenticationCookies]];
}

- (NSData *)loadPageWithURL:(NSURL *)url method:(NSString *)method response:(NSURLResponse **)response error:(NSError **)error {
	return [NSURLConnection sendSynchronousRequest:[self requestForPageWithURL:url method:method] returningResponse:response error:error];
}

- (void)generateTruyyut {
	NSURL *url = [NSURL URLWithString:[@"http://www.educacional.com.br/" stringByAppendingString:[[self sessionInfo] objectForKey:kPortoPortalKey]]];

	NSURLResponse *response;
	NSError *error;
	NSData *portalData = [self loadPageWithURL:url method:@"GET" response:&response error:&error];
	if (portalData == nil) {
		[self setTruyyut:nil];
		return;
	}
	
	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:portalData];
        
        NSString *function = [[[document firstElementMatchingPath:@"/html/body"] content] gtm_stringByUnescapingFromHTML];
	NSRange parRange = [function rangeOfString:@"javascript:fPS_Boletim"];
	if (parRange.location == NSNotFound) {
		[document release];
		[self setTruyyut:nil];
		return;
	}

	NSString *parameter = [function substringFromIndex:parRange.location + parRange.length];
	NSRange closePar = [parameter rangeOfString:@")"];
	NSString *truyyut = [parameter substringWithRange:NSMakeRange(2, closePar.location-3)];
	NSLog(@"TRUYYUT: %@", truyyut);
	[document release];

	[self setTruyyut:truyyut];
}

- (void)generateGradeID {
	if (![self truyyut]) [self generateTruyyut];
	if ([self truyyut] == nil) {
		[self setGradeID:nil];
		return;
	}

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.educacional.com.br/barra_logados/servicos/portoseguro_notasparciais.asp?x=%@", [self truyyut]]];
	NSURLResponse *response;
        NSError *error;
        NSData *data = [self loadPageWithURL:url method:@"GET" response:&response error:&error];
	if (data == nil) {
		[self setGradeID:nil];
		return;
	}

	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
	XMLElement *medElement = [document firstElementMatchingPath:@"/html/body/form/input"];
	if (medElement == nil) {
		[document release];
		[self setGradeID:nil];
		return;
	}

	NSString *token = [[medElement attributes] objectForKey:@"value"];
	NSLog(@"token is %@", token);
	[document release];

	[self setGradeID:token];
}

/* 
Funnily, they have this fun security issue where if you go to iframe_comunicados.asp without any cookies
you will still get a valid token for name "Funcionário".
*/
- (void)generatePapersID {
	//NSURL *papersURL = [NSURL URLWithString:@"http://www.educacional.com.br/rd/gravar.asp?servidor=http://portoseguro.educacional.net&url=/educacional/comunicados.asp"];
	NSURL *papersURL = [NSURL URLWithString:@"http://portoseguro.educacional.net/educacional/iframe_comunicados.asp"];

	NSURLResponse *response;
	NSError *error;
	NSData *papersPageData = [self loadPageWithURL:papersURL method:@"GET" response:&response error:&error];
	if (papersPageData == nil) {
		[self setPapersID:nil];
		return;
	}
	
	// Since libxml doesn't like this page, we'll need to do parsing ourselves.
	// I think this deserves a FIXME.
	const char *pageData = (const char *)[papersPageData bytes];
	char *input = strstr(pageData, "<input");
	char *close = strstr(input, ">");
	char *value = strstr(input, "value");
	if (close <= value) {
		[self setPapersID:nil];
		return;
	}

	value += 7; //strlen("value=\"")
	char *c = value;
	while (*c != '"') c++;
	*c = '\0';
	
	NSLog(@"value is %s", value);
	[self setPapersID:[NSString stringWithUTF8String:value]];
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
	return (![[$webView superclass] instancesRespondToSelector:aSelector] && [$webView respondsToSelector:aSelector]);
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
	[self view]; // FIXME: ?
	return (![self respondsToSelector:aSelector] && [self shouldForwardSelector:aSelector]) ? $webView : self;
}

- (void)loadView {
	[super loadView];
	
	$refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
	$spinnerButton = [[UIBarButtonItem alloc] initWithCustomView:[[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray] autorelease]];
	
	//$webView = [[UIWebView alloc] initWithFrame:CGRectMake(0.f, 0.f, [[UIScreen mainScreen] bounds].size.width, SYSTEM_VERSION_GT_EQ(@"7.0") ? [[UIScreen mainScreen] bounds].size.height : [[UIScreen mainScreen] bounds].size.height-HEIGHT_OF_TABBAR-HEIGHT_OF_NAVBAR-HEIGHT_OF_STATUSBAR+1.f)];
	$webView = [[UIWebView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[$webView setScalesPageToFit:YES];
	[$webView setDelegate:self];
	[$webView setHidden:YES];
	[[self view] addSubview:$webView];

	$failView = [[FailView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[$failView setHidden:YES];
	[[self view] addSubview:$failView];

	$loadingView = [[LoadingIndicatorView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[[self view] addSubview:$loadingView];
}

- (void)viewDidLoad {
        [super viewDidLoad];

	[[self navigationItem] setRightBarButtonItem:$spinnerButton];
	[(UIActivityIndicatorView *)[$spinnerButton customView] startAnimating];
        
	// I don't want this to be so, but UIWebView has some sort of bug when loading pdf's that'll make it require it :(
	if (SYSTEM_VERSION_GT_EQ(@"7.0"))
                [self setAutomaticallyAdjustsScrollViewInsets:NO];
	
	[[$loadingView activityIndicatorView] startAnimating];
}

- (void)reload {
	[$webView reload];

	[$webView setHidden:YES];
	[$failView setHidden:YES];
	
	[$loadingView setHidden:NO];
	[[$loadingView activityIndicatorView] startAnimating];

	[[self navigationItem] setRightBarButtonItem:$spinnerButton];
	[(UIActivityIndicatorView *)[$spinnerButton customView] startAnimating];
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

- (UIWebView *)webView {
	return $webView;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
	[$loadingView setHidden:YES];
	[[$loadingView activityIndicatorView] stopAnimating];
	[$failView setHidden:YES];

	[[self navigationItem] setRightBarButtonItem:$refreshButton];
	[(UIActivityIndicatorView *)[$spinnerButton customView] stopAnimating];

	[[self webView] setHidden:NO];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
	[$loadingView setHidden:YES];
	[[$loadingView activityIndicatorView] stopAnimating];
	[[self webView] setHidden:YES];

	[[self navigationItem] setRightBarButtonItem:$refreshButton];
	[(UIActivityIndicatorView *)[$spinnerButton customView] stopAnimating];
	
	[$failView setTitle:@"Erro de request"];
	[$failView setText:@"Não pôde carregar o link especificado."];
	[$failView setNeedsLayout];
	[$failView setHidden:NO];
}

- (void)dealloc {
	[$webView release];
	[$loadingView release];
	
	[super dealloc];
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

- (id)initWithIdentifier:(NSString *)identifier {
	return [self initWithIdentifier:identifier cacheIdentifier:@"0"];
}

- (id)initWithIdentifier:(NSString *)identifier_ cacheIdentifier:(NSString *)cacheIdentifier_ {
	if ((self = [super init])) {
		char *identifier;
		asprintf(&identifier, "am.theiostre.portoapp.webdata.%s", [identifier_ UTF8String]);
		
		$queue = dispatch_queue_create(identifier, NULL);
		//dispatch_retain($queue);
		free(identifier);
		
		$cacheIdentifier = [cacheIdentifier_ retain];
		NSString *cacheFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-Cache", NSStringFromClass([self class]), [self cacheIdentifier]]];		
		$cachedData = [[NSData alloc] initWithContentsOfFile:cacheFile];

	}

	return self;
}

- (CGRect)contentViewFrame {
	CGRect bounds = FixViewBounds([[self view] bounds]);
	if ([self shouldUseCachedData]) {
		bounds.origin.y += 20;
		bounds.size.height -= 20;
	}

	return bounds;
}

- (NSString *)cacheIdentifier {
	return $cacheIdentifier;
}

- (void)loadView {
	[super loadView];
	
	$refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
	$spinnerButton = [[UIBarButtonItem alloc] initWithCustomView:[[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray] autorelease]];

	$loadingView = [[LoadingIndicatorView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[[self view] addSubview:$loadingView];

	$failureView = [[FailView alloc] initWithFrame:FixViewBounds([[self view] bounds])];
	[$failureView setHidden:YES];
	[[self view] addSubview:$failureView];
	
	$contentView = nil;
	[self loadContentView];
	[$contentView setHidden:YES];
	[[self view] addSubview:$contentView];

	$cacheView = [[UIView alloc] initWithFrame:CGRectMake(0, [self contentViewFrame].origin.y-20, [[self view] bounds].size.width, 20)];
	[$cacheView setHidden:YES];
	
	UILabel *cachedLabel = [[UILabel alloc] initWithFrame:[$cacheView bounds]];
	[cachedLabel setText:@"Página Não Atualizada"];
	[cachedLabel setFont:[UIFont systemFontOfSize:pxtopt(20.f)]];
	[cachedLabel setTextColor:[UIColor blackColor]];
	[cachedLabel setBackgroundColor:[UIColor clearColor]];
	[cachedLabel setTextAlignment:NSTextAlignmentCenter];
	[$cacheView addSubview:cachedLabel];
        [cachedLabel release];
	[[self view] addSubview:$cacheView];
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
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if (!SYSTEM_VERSION_GT_EQ(@"6.0")) [self $freeViews];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector($notificationRefresh:) name:@"PortoDidPerformLogin" object:nil];
	[self refresh];

	// TODO: Add a session id check here (would be convenient)
}

- (void)$notificationRefresh:(NSNotification *)notification {
	[self refresh];
}

- (void)refresh {
	[self $performUIBlock:^{
		[self displayLoadingView];
		
		[[self navigationItem] setRightBarButtonItem:$spinnerButton];
		[(UIActivityIndicatorView *)[$spinnerButton customView] startAnimating];
	}];
	
	void (^reloadData)() = ^{
                [self reloadData];
                
		[self $performUIBlock:^{
			[(UIActivityIndicatorView *)[$spinnerButton customView] stopAnimating];
			if ([self allowsRefresh]) [[self navigationItem] setRightBarButtonItem:$refreshButton];
		}];
	};
	
	if ([NSThread isMainThread]) dispatch_async($queue, reloadData);
	else reloadData();
}

- (void)reloadData {
	[self displayContentView];
}

- (BOOL)allowsRefresh {
	return YES;
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
		[$cacheView setHidden:YES];
	}];
}

- (void)displayFailViewWithTitle:(NSString *)title text:(NSString *)text {
	[self $performUIBlock:^{
		[self hideLoadingView];
		[self hideContentView];
		
		[$failureView setTitle:title];
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

		[$cacheView setHidden:![self shouldUseCachedData]];
		[$cacheView setFrame:CGRectMake(0, [self contentViewFrame].origin.y-20, [[self view] bounds].size.width, 20)];
		[$contentView setFrame:[self contentViewFrame]];
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
	$contentView = [[UIView alloc] initWithFrame:[self contentViewFrame]];
}

- (void)unloadContentView {
	return;
}

- (void)$freeViews {
	[$refreshButton release];
	[$spinnerButton release];

	[$loadingView release];
	[$failureView release];
	[$cacheView release];
	
	[self unloadContentView];
	[$contentView release];
}

//#define ALWAYS_CACHE
- (BOOL)shouldUseCachedData {
	if (!$cachedData) return NO;
	#ifdef ALWAYS_CACHE
	return YES;
	#else	
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "www.educacional.com.br");
	SCNetworkReachabilityFlags flags;
	SCNetworkReachabilityGetFlags(reachability, &flags);

	NetworkStatus status = NotReachable;
	if ((flags & kSCNetworkReachabilityFlagsReachable) != 0) {
		if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
			status = ReachableViaWiFi;
		}
		
		if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0) ||
		      (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0)) {
			if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
				status = ReachableViaWiFi;
			}
		}

		if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
			status = ReachableViaWWAN;
		}
	}
	CFRelease(reachability);

	return status == NotReachable;
	#endif
}

- (NSData *)cachedData {
	return $cachedData;
}

- (void)cacheData:(NSData *)data {
	if ($cachedData) [$cachedData release];
	$cachedData = [data retain];

	NSString *cacheFile = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-Cache", NSStringFromClass([self class]), [self cacheIdentifier]]];
	[$cachedData writeToFile:cacheFile atomically:YES];
}

- (void)dealloc {
	[self $freeViews];
	[self freeData];
	if ($cachedData) [$cachedData release];
	[$cacheIdentifier release];
	
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
        [loadingIndicatorView release];
	
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
			[controller generateGradeID];
			[controller generatePapersID];

			[[NSNotificationCenter defaultCenter] postNotificationName:@"PortoDidPerformLogin" object:nil];			
		}

		[self endRequestWithSuccess:success error:error];
	}];
}
@end
/* }}} */

/* }}} */

/* News Controller {{{ */

@implementation NavigationWebBrowserController
- (id)initWithQueue:(dispatch_queue_t)queue {
	if ((self = [super init])) {
		dispatch_retain(queue);
		$queue = queue;
	}

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Sem Título"];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
	// Perform JavaScript optimizations here.
	if ([[[[webView request] URL] absoluteString] isEqualToString:@"http://arquivos.portoseguro.org.br/Emails/AconteceNoPorto/AconteceNoPorto.html"]) {
		[self executeJavascript:@"document.getElementsByTagName('table')[0].setAttribute('style', 'position:absolute;top:0;bottom:0;left:0;right:0;width:100%;height:100%;border:1px;solid');"];
		[self executeJavascript:@"document.getElementsByTagName('td')[1].setAttribute('align', 'center')"];

		[self setTitle:@"Acontece No Porto"];
	}
	else if ([[[[webView request] URL] absoluteString] hasPrefix:@"http://arquivos.portoseguro.org.br/emails"]) {
		[self executeJavascript:@"document.body.removeChild(document.getElementsByTagName('table')[0]);"];
		[self executeJavascript:@"document.getElementsByTagName('table')[0].setAttribute('style', 'position:absolute;top:0;bottom:0;left:0;right:0;width:100%;height:100%;border:1px;solid');"];

		[self setTitle:@"Acontece No Porto"];
	}
	else {
		NSString *pageTitle = [self executeJavascript:@"document.title"];
		if (!pageTitle || [pageTitle length]<1) pageTitle = @"Sem Título";
		[self setTitle:pageTitle];
	}		

	[super webViewDidFinishLoad:webView];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
	if (navigationType == UIWebViewNavigationTypeLinkClicked) {
		NSURL *url = [request URL];
		if (![[url host] isEqualToString:@"www.portoseguro.org.br"] || [[url absoluteString] rangeOfString:@"noticia"].location == NSNotFound) {
			NavigationWebBrowserController *browser = [[[NavigationWebBrowserController alloc] initWithQueue:$queue] autorelease];
			[browser loadRequest:request];
			[[self navigationController] pushViewController:browser animated:YES];
		}
		else {
			NewsArticleWebViewController *article = [[[NewsArticleWebViewController alloc] initWithQueue:$queue newsURL:url] autorelease];
			[article loadLocalFile:[[NSBundle mainBundle] pathForResource:@"news_base" ofType:@"html"]];
			[[self navigationController] pushViewController:article animated:YES];
		}
		
		return NO;
	}

	return YES;
}

- (void)dealloc {
	dispatch_release($queue);
	[super dealloc];
}
@end

@implementation NewsArticleWebViewController
- (id)initWithQueue:(dispatch_queue_t)queue newsURL:(NSURL *)newsURL {
	if ((self = [super init])) {
		dispatch_retain(queue);
                $queue = queue;
		$newsURL = [newsURL retain];
	}

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Notícia"];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
	dispatch_async($queue, ^{
		NSData *data = [NSData dataWithContentsOfURL:$newsURL];
		if (data == nil) {
			dispatch_sync(dispatch_get_main_queue(), ^{
				[self executeJavascript:@"document.body.innerHTML='<h1>ERRO DE CONEXÃO (newsload:baddata).</h1> <h3>Contate q@theiostream.com e descreva o problema.</h3>';"];
				[super webViewDidFinishLoad:webView];
			});
			
			return;
		}
		
		XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
		XMLElement *newsElement = [document firstElementMatchingPath:@"/html/body/div[@id='main']/section//div[starts-with(@class, 'conteudo')]"];
		if (newsElement == nil) {
			// If we have no conteudo, then we load the page without any extra formatting.
			[self loadHTMLString:[NSString stringWithUTF8String:(const char *)[data bytes]] baseURL:[NSURL URLWithString:kPortoRootURL]];
		}

		NSString *newsContent = [newsElement content];
		[document release];
		
		// FIXME: Sometimes stuff will get screwed-up when there's like an image gallery.
		// Example: https://www.portoseguro.org.br/noticia/detalhe/prazer-pela-cincia
		dispatch_sync(dispatch_get_main_queue(), ^{
			// Firstly, we add Porto's data into our base html.
			[self executeJavascript:[NSString stringWithFormat:@"var el = document.getElementById('portoAppInsertContent'); el.innerHTML='%@';", [[[[newsContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"] stringByReplacingOccurrencesOfString:@"\t" withString:@"\t\t"]]];
			
			// Secondly, we fix an error thanks to them not checking their quotations.
			/* Source code: <div id="share2"><div class="fb-share-button" data-href=""https://www.portoseguro.org.br//noticia/unidade/morumbi/inovao-com-mit"" data-type="box_count"></div></div> (works on WebKit!)
			   Rendered by libxml2: <div id="share2"><div class="fb-share-button" data-href="" https:="" data-type="box_count"/></div> (doesn't close share2)
			   Since share2 has a big margin to the right, we need to patch that to get a decent page.
			*/
			[self executeJavascript:@"var el = document.getElementById('share'); el.style.margin = '0 -10px 0 17px';"];
			[self executeJavascript:@"var el = document.getElementById('share2'); el.style.margin = '0 -10px 0 17px';"];
			
			// Thirdly, we optimize the page for a better reading experience.
			[self executeJavascript:@"var p = document.getElementsByTagName('p'); for(i=0; i<p.length; i++) { p[i].style.fontSize='48px'; p[i].style.fontFamily='Helvetica Neue'; p[i].style.lineHeight='1.4'; }"];
			/* " do not remove this comment else vim will get mad. */
			[self executeJavascript:@"var el = document.getElementsByTagName('h2')[0]; el.style.fontSize='84px';"];
			[self executeJavascript:@"var el = document.getElementsByTagName('h4')[0]; el.style.marginTop='28px'; el.style.fontSize='96px';"];

			[super webViewDidFinishLoad:webView];			
		});
	});
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
	if (navigationType == UIWebViewNavigationTypeLinkClicked) {
		NSURL *url = [request URL];
		if (![[url host] isEqualToString:@"www.portoseguro.org.br"] || [[url absoluteString] rangeOfString:@"noticia"].location == NSNotFound) {
			NavigationWebBrowserController *browser = [[[NavigationWebBrowserController alloc] initWithQueue:$queue] autorelease];
			[browser loadRequest:request];
			[[self navigationController] pushViewController:browser animated:YES];
		}
		else {
			NewsArticleWebViewController *article = [[[NewsArticleWebViewController alloc] initWithQueue:$queue newsURL:url] autorelease];
			[article loadLocalFile:[[NSBundle mainBundle] pathForResource:@"news_base" ofType:@"html"]];
			[[self navigationController] pushViewController:article animated:YES];
		}
		
		return NO;
	}

	return YES;
}

- (void)dealloc {
	dispatch_release($queue);
	[$newsURL release];
	
	[super dealloc];
}
@end

@implementation NewsTableViewCell
@synthesize newsImage = $newsImage, newsTitle = $newsTitle, newsSubtitle = $newsSubtitle;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
		$imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0.f, 0.f, [self bounds].size.width, 130.f)];
		[self addSubview:$imageView];
	}

	return self;
}

// FIXME: The gray thing over the view when it's tapped should actually show up.
- (void)drawContentView:(CGRect)rect highlighted:(BOOL)highlighted {
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CGContextTranslateCTM(context, 0, [self bounds].size.height);
        CGContextScaleCTM(context, 1.0, -1.0);

        [[UIColor whiteColor] setFill];
        CGContextFillRect(context, rect);

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
        
        CGContextSetTextPosition(context, 5.f, [self bounds].size.height - 150.f);
        CTLineDraw(line, context);
        CFRelease(line);

        CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)subtitleString);
        [subtitleString release];
        
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, CGRectMake(5.f, 6.f, [self bounds].size.width - 10.f, [self bounds].size.height - 160.f));
        CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, NULL);
        CFRelease(path);
        CFRelease(framesetter);

        CGContextSetTextPosition(context, 0.f, 0.f); // idk if i need this but it works
        CTFrameDraw(frame, context);
        CFRelease(frame);

        if (highlighted) {
                [UIColorFromHexWithAlpha(0x7c7c7c, 0.4) setFill];
                CGContextFillRect(context, rect);
        }        
}

- (void)setNewsImage:(UIImage *)img {
	if ($newsImage) [$newsImage release];

	[$imageView setImage:img];
	$newsImage = [img retain]; // FIXME: Do we need this reference?
}

- (void)dealloc {
        [$newsImage release];
        [$newsTitle release];
        [$newsSubtitle release];

	[$imageView release];

        [super dealloc];
}
@end

@implementation NewsViewController
- (id)initWithIdentifier:(NSString *)identifier {
	if ((self = [super initWithIdentifier:identifier])) {
		$imageData = [[NSMutableArray alloc] init];
	}

	return self;
}

- (void)loadContentView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:[self contentViewFrame] style:UITableViewStylePlain];
	[tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
	[tableView setDelegate:self];
	[tableView setDataSource:self];

	$contentView = tableView;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Notícias"];
}	

- (void)reloadData {
	//[super reloadData];
	[$imageData removeAllObjects];

	NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://www.portoseguro.org.br"]];
	if (data == nil) {
		[self displayFailViewWithTitle:@"Falha ao carregar página." text:@"Cheque sua conexão de Internet."];
		return;
	}

	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
	NSArray *list = [document elementsMatchingPath:@"/html/body/div[@id = 'main']/div[@id = 'banner']/div[@id = 'bannerFoto']/ul/li"];
	
	for (XMLElement *banner in list) {
		XMLElement *a = [banner firstElementMatchingPath:@"./a"];
		NSString *porto, *link;
		
		NSString *function = [[a attributes] objectForKey:@"onclick"];
		if ([function length] > 0) {
			NSRange ad = [function rangeOfString:@"Ad"];
			link = [function substringWithRange:NSMakeRange(ad.location + 4, [function length]-(ad.location+4)-2)];
			NSLog(@"LINK IS %@", link);

			NSDictionary *unidadeMap = [NSDictionary dictionaryWithObjectsAndKeys:
				@"Morumbi", @"morum",
				@"Valinhos", @"valin",
				@"Panamby", @"panan",
				nil];

			NSString *portoId = [function substringToIndex:5];
			porto = [unidadeMap objectForKey:portoId];
		}
		else {
			link = [[a attributes] objectForKey:@"href"];
			NSLog(@"LINK FOR INST IS %@", link);
			porto = @"Institucional";
		}
		
		XMLElement *title = [banner firstElementMatchingPath:@"./div/h2/a"];
		XMLElement *subtitle = [banner firstElementMatchingPath:@"./div/p/a"];

		XMLElement *img = [banner firstElementMatchingPath:@".//a/img"];
		UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[kPortoRootURL stringByAppendingString:[[img attributes] objectForKey:@"src"]]]]];

		NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
			porto, @"Porto",
			link, @"Link",
			[title content], @"Title",
			[subtitle content], @"Subtitle",
			image, @"Image",
			nil];
		[$imageData addObject:result];
	}
	
	XMLElement *box12 = [document firstElementMatchingPath:@"/html/body/div[@id='main']/section/div[@class='box1-2']"];
	XMLElement *img = [box12 firstElementMatchingPath:@"./div[@class='box1Foto']/a/img"];
	UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[kPortoRootURL stringByAppendingString:[[img attributes] objectForKey:@"src"]]]]];

	XMLElement *extraElement = [box12 firstElementMatchingPath:@"./div[@class='box1Faixa']"];
	XMLElement *extraElementA = [extraElement firstElementMatchingPath:@"./h4/a"];
	NSDictionary *extra = [NSDictionary dictionaryWithObjectsAndKeys:
		[[[extraElement firstElementMatchingPath:@"./h3"] content] substringFromIndex:3], @"Porto",
		[kPortoRootURL stringByAppendingString:[[extraElementA attributes] objectForKey:@"href"]], @"Link",
		[[extraElementA firstElementMatchingPath:@"./strong"] content], @"Subtitle",
		@"Especial", @"Title",
		image, @"Image",
		nil];
	[$imageData addObject:extra];

	NSDictionary *more = [NSDictionary dictionaryWithObjectsAndKeys:
		@"Arquivo", @"Porto",
		@"$AconteceNoPorto", @"Link",
		@"Acontece no Porto", @"Title",
		@"Veja aqui um catálogo de todas as notícias arquivadas.", @"Subtitle",
		[UIImage imageNamed:@"acontece_no_porto.gif"], @"Image",
		nil];
	[$imageData addObject:more];
	
	[document release];

	[self $performUIBlock:^{
		UITableView *tableView = (UITableView *)[self contentView];
		[tableView reloadData];

		[self displayContentView];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [$imageData count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return 30.f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *subtitle = [[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Subtitle"];
	CGSize subtitleSize = [subtitle sizeWithFont:[UIFont systemFontOfSize:16.f] constrainedToSize:CGSizeMake([tableView bounds].size.width - 6.f, CGFLOAT_MAX)];
	return 160.f + subtitleSize.height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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
	static NSString *cellIdentifier = @"PortoNewsHeaderViewIdentifier";
	UITableViewHeaderFooterView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:cellIdentifier];
	if (headerView == nil) {
		headerView = [[[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:cellIdentifier] autorelease];
		[[headerView contentView] setBackgroundColor:UIColorFromHexWithAlpha(0x203259, 1.f)];

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(5.f, 3.f, [tableView bounds].size.width - 12.f, 24.f)];
		[label setBackgroundColor:[UIColor clearColor]];
		[label setTextColor:[UIColor whiteColor]];
		[label setFont:[UIFont systemFontOfSize:19.f]];
		[label setTag:87];
		[[headerView contentView] addSubview:label];
		
		[label release];
	}
	
	NSString *text = [[$imageData objectAtIndex:section] objectForKey:@"Porto"];
	if ([text isEqualToString:@""]) text = @"Institucional";
	
	[(UILabel *)[headerView viewWithTag:87] setText:text];

	return headerView;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *link = [[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Link"];
	if (![link isEqualToString:@"$AconteceNoPorto"]) {
		NewsArticleWebViewController *controller = [[[NewsArticleWebViewController alloc] initWithQueue:$queue newsURL:[NSURL URLWithString:link]] autorelease];
		[controller loadLocalFile:[[NSBundle mainBundle] pathForResource:@"news_base" ofType:@"html"]];
		[[self navigationController] pushViewController:controller animated:YES];
	}
	else {
		NavigationWebBrowserController *controller = [[[NavigationWebBrowserController alloc] initWithQueue:$queue] autorelease];
		[controller loadPage:@"http://arquivos.portoseguro.org.br/Emails/AconteceNoPorto/AconteceNoPorto.html"];
		[[self navigationController] pushViewController:controller animated:YES];
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)dealloc {
	[$imageData release];
	[super dealloc];
}
@end

/* }}} */

/* Grades Controller {{{ */

// TODO Add a page control.
@implementation GradesListViewController
@synthesize year = $year, period = $period;

- (id)init {
	return nil;
}

- (GradesListViewController *)initWithYear:(NSString *)year period:(NSString *)period viewState:(NSString *)viewState eventValidation:(NSString *)eventValidation {
	if ((self = [super initWithIdentifier:@"GradesListView" cacheIdentifier:[NSString stringWithFormat:@"%@_%@", year, period]])) {
		$viewState = [viewState retain];
		$eventValidation = [eventValidation retain];

		[self setYear:year];
		[self setPeriod:period];

		$rootContainer = nil;
	}

	return self;
}

- (void)$notificationRefresh:(NSNotification *)notification {
	[[self navigationController] popToRootViewControllerAnimated:YES];
	[super $notificationRefresh:notification];
}

- (void)reloadData {
	//[super reloadData];
	SessionController *sessionController = [SessionController sharedInstance];

	if ($rootContainer != nil) {
		[$rootContainer release];
	}
	[self $performUIBlock:^{
		[[$contentView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	}];

	NSData *data;
	IfNotCached {
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

		data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:&error];
		if (data == nil) {
			[self displayFailViewWithTitle:@"Falha ao carregar página." text:@"Cheque sua conexão de Internet."];
			return;
		}

		NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
		if (statusCode != 200) {
			if (statusCode == 500) {
				// The JavaScript handler for the 500 error tells me to contact the IT team.
				// And it also redirects me to a login page which I CANNOT USE SINCE IT'S A WHOLE DIFFERENT LOGIN DOMAIN
				// WHAT THE FUCK

				// So they throw a 500 both for missing grades /and/ general-errors.
				// It's up to us to determine which one of those it is.
				// Let's hope a guess with the expected backtrace is good enough.

				NSString *backtrace = [NSString stringWithUTF8String:(char *)[data bytes]];
				if ([backtrace rangeOfString:kMissingGradesBacktraceStackTop].location != NSNotFound)
					[self displayFailViewWithTitle:@"Notas Não Encontradas" text:@"O período selecionado não pôde ser encontrado.\n\n(Há uma chance de isto ser um erro HTTP 500. Neste caso, tente recarregar a página ou espere o site se recuperar do problema.)"];
				else
					[self displayFailViewWithTitle:@"Erro HTTP 500" text:@"Houve um erro de servidor." kServerError];
			}
			else if (statusCode == 12030) {
				[self displayFailViewWithTitle:@"Erro HTTP 12030" text:@"A conexão com o servidor foi abortada (e o Porto está preparado para isso com um alerta na página de Notas!)." kServerError];
			}
			else {
				[self displayFailViewWithTitle:[NSString stringWithFormat:@"Erro HTTP %d", statusCode] text:@"Houve um erro de servidor desconhecido." kServerError];
			}

			return;
		}
		#endif

		// i used this because 3rd period of 2013 was going to be concluded
		// so i still needed to test this on an incomplete period.
		// so i saved this html file. i know it's a horrible test with few cases, but i'll be creative etc.
		//#define SAVE_GRADE_HTML
		#ifdef SAVE_GRADE_HTML
		[data writeToFile:@"/Users/BobNelson/Documents/Projects/PortoApp/datak.html" atomically:NO];
		#endif

		[self cacheData:data];
	}
	ElseNotCached(data);

	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
        NSLog(@"%@", [[document firstElementMatchingPath:@"/html/body"] content]);
        
	XMLElement *divGeral = [document firstElementMatchingPath:@"/html/body/form[@id='form1']/div[@class='page ui-corner-bottom']/div[@class='body']/div[@id='updtPnl1']"];
	//if ([[[divGeral firstElementMatchingPath:@"./span[@id='ContentPlaceHolder1_lblMsg']"] content] isEqualToString:kNoGradesLabelText]) {
        if ([divGeral firstElementMatchingPath:@"./span[@id='ContentPlaceHolder1_lblMsg']"]) {
		[self displayFailViewWithTitle:@"Notas Não Encontradas" text:@"O período selecionado não pôde ser encontrado."];

		[document release];
		return;
	}

	XMLElement *table = [divGeral firstElementMatchingPath:@"./table[@id='ContentPlaceHolder1_dlMaterias']"];
	NSArray *subjectElements = [table elementsMatchingPath:@"./tr/td/div[@class='container']"];
	
	$rootContainer = [[GradeContainer alloc] init];
	[$rootContainer setDebugLevel:0];
	[$rootContainer setWeight:1];
	[$rootContainer setName:@"Nota Total"];
	[$rootContainer makeValueTen];
	
	NSMutableArray *subjectContainers = [NSMutableArray array];
	for (XMLElement *container in subjectElements) {
		GradeContainer *subjectContainer = [[GradeContainer alloc] init];
		NSLog(@"ALLOCATED RIGHT? %p", subjectContainer);
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
		NSLog(@"INIT SUBJECT CONTAINER WITH NAME %@ %p", subjectName, subjectContainer);
		
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
			GradeContainer *subGradeContainer = [[GradeContainer alloc] init];
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
					GradeContainer *subsubsectionGradeContainer = [[GradeContainer alloc] init];
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
					[subsubsectionGradeContainer release];
				}
			}
			
			[subGradeContainer setSubGradeContainers:subsubGradeContainers];
			[subGradeContainers addObject:subGradeContainer];
			[subGradeContainer release];
		}

		NSMutableArray *subBonusContainers = [NSMutableArray array];
		NSArray *bonusGrades = [[container firstElementMatchingPath:@"./div/table[starts-with(@id, 'ContentPlaceHolder1_dlMaterias_gvAtividades')]"] elementsMatchingPath:@"./tr"];
		if (bonusGrades != nil) {
			for (XMLElement *subsection in bonusGrades) {
				GradeContainer *bonusContainer = [[GradeContainer alloc] init];
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
				[bonusContainer release];
			}
		}
		
		[subjectContainer setSubGradeContainers:subGradeContainers];
		[subjectContainer setSubBonusContainers:subBonusContainers];
		[subjectContainers addObject:subjectContainer];
		NSLog(@"RELEASE! %p", subjectContainer);
		[subjectContainer release];
	}

	[document release];
	
	[$rootContainer setSubGradeContainers:subjectContainers];
	[$rootContainer calculateGradeFromSubgrades];
	[$rootContainer calculateAverageFromSubgrades];
	
	/*      Cristina Santos: Olha só parabéns u.u
		Cristina Santos: Gostei de ver
	NSLog(@"%@", $rootContainer); */
        
	[self $performUIBlock:^{
		[(UICollectionView *)$contentView reloadData];
		[self displayContentView];
	}];
}

- (void)loadContentView {
	/*NoButtonDelayScrollView *scrollView = [[NoButtonDelayScrollView alloc] initWithFrame:[self contentViewFrame]];
	[scrollView setBackgroundColor:[UIColor whiteColor]];
	[scrollView setScrollsToTop:NO];
	[scrollView setPagingEnabled:YES];

	$contentView = scrollView;*/

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	[layout setScrollDirection:UICollectionViewScrollDirectionHorizontal];

	UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:[self contentViewFrame] collectionViewLayout:layout];
	[layout release];

	[collectionView setDataSource:self];
	[collectionView setDelegate:self];
	[collectionView registerClass:[GradesSubjectView class] forCellWithReuseIdentifier:@"GradeSubjectViewIdentifier"];
	[collectionView setBackgroundColor:[UIColor whiteColor]];
	[collectionView setScrollsToTop:NO];
	[collectionView setPagingEnabled:YES];

	$contentView = collectionView;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	if ($rootContainer == nil) return 0;
	return [[$rootContainer subGradeContainers] count];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return 1;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	return [collectionView bounds].size;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	GradesSubjectView *cell = (GradesSubjectView *)[collectionView dequeueReusableCellWithReuseIdentifier:@"GradeSubjectViewIdentifier" forIndexPath:indexPath];
	[cell setContainer:[[$rootContainer subGradeContainers] objectAtIndex:[indexPath section]]];

	return cell;
}

/*- (void)prepareContentView {
	NoButtonDelayScrollView *contentView = (NoButtonDelayScrollView *)$contentView;
	NSArray *subjectContainers = [$rootContainer subGradeContainers];

	CGRect subviewRect = CGRectMake(0.f, 0.f, [contentView bounds].size.width, [contentView bounds].size.height);
	for (GradeContainer *subject in subjectContainers) {
		GradesSubjectView *subjectView = [[[GradesSubjectView alloc] initWithFrame:subviewRect container:subject] autorelease];
		[contentView addSubview:subjectView];

		subviewRect.origin.x += subviewRect.size.width;
	}
	[contentView setContentSize:CGSizeMake(subviewRect.origin.x, [contentView bounds].size.height)];
}*/

- (void)dealloc {
	NSLog(@"GradesListViewController dealloc");

	[$viewState release];
	[$eventValidation release];
	[$year release];
	[$period release];

	[$rootContainer release];

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
	[[self view] setBackgroundColor:[UIColor whiteColor]];
}

- (void)reloadData {
	//[super reloadData];

	[$yearOptions removeAllObjects];
	[$periodOptions removeAllObjects];

	NSData *data;
	IfNotCached {
		SessionController *sessionController = [SessionController sharedInstance];
		if (![sessionController hasSession]) {
			[self displayFailViewWithTitle:@"Sem autenticação" text:@"Realize o login no menu de Contas."];
			return;
		}
		if (![sessionController gradeID]) {
			[sessionController generateGradeID]; // it doesn't cost to try...
			if (![sessionController gradeID]) {
				[self displayFailViewWithTitle:@"Sem ID de Notas" text:@kReportIssue];
				return;
			}
		}
		
		if ($viewState != nil) [$viewState release];
		if ($eventValidation != nil) [$eventValidation release];
		$viewState = nil;
		$eventValidation = nil;

		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://notasparciais.portoseguro.org.br/notasparciais.aspx?token=%@", [sessionController gradeID]]];
		NSURLResponse *response;
		data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:NULL];
		if (data == nil) {
			[self displayFailViewWithTitle:@"Falha ao carregar página." text:@"Cheque sua conexão de Internet."];
			return;
		}

		[self cacheData:data];
	}
	ElseNotCached(data);
	
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
		[self displayFailViewWithTitle:@"Erro de Interpretação" text:@"Erro: notasparciais.aspx:ViewState/EventValidation" kReportIssue];
                [document release];
		return;
	}
	
	NSString *m3tPath = @"/html/body/form[@id='form1']/div[@class='page ui-corner-bottom']/div[@class='body']/div[@id='updtPnl1']/div[@id='ContentPlaceHolder1_divGeral']/div[@class='container']/div[@class='fleft']/div[@class='m3t']";
	XMLElement *yearSelect = [document firstElementMatchingPath:[m3tPath stringByAppendingString:@"/select[@name='ctl00$ContentPlaceHolder1$ddlAno']"]];
	XMLElement *periodSelect = [document firstElementMatchingPath:[m3tPath stringByAppendingString:@"/select[@name='ctl00$ContentPlaceHolder1$ddlEtapa']"]];
	
	NSArray *yearOptionElements = [yearSelect elementsMatchingPath:@"./option"];
	for (XMLElement *element in yearOptionElements) {
		Pair *p = [[[Pair alloc] initWithObjects:[element content], [[element attributes] objectForKey:@"value"]] autorelease];
		[$yearOptions addObject:p];
	}
	
	if ([$yearOptions count] == 0) {
		[self displayFailViewWithTitle:@"Erro de Interpretação" text:@"Erro: notasparciais.aspx:Select" kReportIssue];
                [document release];
		return;
	}
	
	/* So, one may wonder like "wait what we're only checking the options for the currently selected year and not for all
	 * years.
	 * The thing is, such information for each year is not in the view state and I will /NOT/ do a fuckload of postbacks
	 * to this page just to fucking find out something that seems to be constant across years.
	 * So that'll be it until Porto decides to change how stuff currently works. */
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
	UITableView *tableView = [[UITableView alloc] initWithFrame:[self contentViewFrame] style:UITableViewStylePlain];
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
		[cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
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
	[listController setTitle:[NSString stringWithFormat:@"%@ (%@)", periodValue_->obj1, yearValue_->obj1]];
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
	NSLog(@"GradesViewController dealloc");

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

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Circulares"];
}

- (void)reloadData {
	//[super reloadData];
	if (self == [[[self navigationController] viewControllers] objectAtIndex:0]) {
		if ($folder != NULL) $folder = NULL;
		if ($viewState != NULL) { free_viewstate($viewState); $viewState = NULL; }

		SessionController *sessionController = [SessionController sharedInstance];
		if (![sessionController hasSession]) {
			[self displayFailViewWithTitle:@"Sem autenticação." text:@"Realize login no menu de Contas."];
			return;
		}
		if (![sessionController papersID]) {
			NSLog(@"err id");
			[self displayFailViewWithTitle:@"Sem ID de Circulares" text:@kReportIssue];
			return;
		}

		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?token=%@", kPortoRootCircularesPage, [sessionController papersID]]];
		NSURLResponse *response;
		NSData *data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:NULL];
		if (data == nil) {
			NSLog(@"err intern");
			[self displayFailViewWithTitle:@"Falha ao carregar a página" text:@"Cheque sua conexão de Internet."];
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
			[self displayFailViewWithTitle:@"Erro de Interpretação" text:@"Erro: base64_decode()" kReportIssue];
			[document release];
			return;
		}
		
		$viewState = parse_viewstate((unsigned char **)&str, true);
		if ($viewState->stateType == kViewStateTypeError) {
			NSLog(@"err vs");
			[self displayFailViewWithTitle:@"Erro de Interpretação" text:@"Erro: parse_viewstate()" kReportIssue];
			[document release];
			return;
		}
		
		$folder = $viewState->pair->first->pair->second->pair->second->arrayList[1]->pair->second->arrayList[9]->pair->first->array->array[1]->array->array[1]->array->array[1];
		NSLog(@"$folder ptr %p", $folder);
		[document release];
	}
        
        [self $performUIBlock:^{
                UITableView *tableView = (UITableView *)[self contentView];
                [tableView reloadData];
                
                NSLog(@"DISPLAY CONTENT VIEW!!");
                [self displayContentView];
        }];

	NSLog(@"END RELOADDATA");	
}

- (BOOL)allowsRefresh {
	return self == [[[self navigationController] viewControllers] objectAtIndex:0];
}

- (void)loadContentView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:[self contentViewFrame] style:UITableViewStylePlain];
	[tableView setDelegate:self];
	[tableView setDataSource:self];

	$contentView = tableView;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
        return $folder == NULL ? 0 : $folder->length-1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PortoAppCirculares"];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PortoAppCirculares"] autorelease];
		
		UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedScrollView:)];
		UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(SYSTEM_VERSION_GT_EQ(@"7.0") ? 15.f : 8.f, [cell bounds].origin.y, [cell bounds].size.width - 20.f, [cell bounds].size.height)];
		[scrollView setBackgroundColor:[UIColor whiteColor]];
		[scrollView addGestureRecognizer:tapGestureRecognizer];
		[tapGestureRecognizer release];
		//[scrollView setBounces:NO];

		UILabel *label = [[UILabel alloc] initWithFrame:[cell bounds]];
		[label setTextColor:[UIColor blackColor]];
		[label setBackgroundColor:[UIColor clearColor]];
		[label setFont:SYSTEM_VERSION_GT_EQ(@"7.0") ? [[cell textLabel] font] : [UIFont boldSystemFontOfSize:20.f]];
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
	
	[scrollView setFrame:(CGRect){[scrollView frame].origin, {isFolder ? ([cell bounds].size.width-20.f)-18.f : [scrollView frame].size.width, [scrollView frame].size.height}}];
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
	if ($viewState != NULL)
		free_viewstate($viewState);

	[super dealloc];
}
@end

/* }}} */

/* Services Controller {{{ */

/* Custom Services {{{ */

/* Class {{{ */

@implementation ClassViewController
- (NSString *)serviceName {
	return @"Turma Atual";
}

- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor whiteColor]];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:[self serviceName]];
}

- (void)reloadData {
	NSData *data;
	IfNotCached {
		SessionController *sessionController = [SessionController sharedInstance];
		if (![sessionController gradeID]) {
			[sessionController generateGradeID];
			if (![sessionController gradeID]) {
				[self displayFailViewWithTitle:@"Sem ID de Notas." text:@kReportIssue];
				return;
			}
		}

		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.turmadoaluno.portoseguro.org.br/?token=%@", [sessionController gradeID]]];
		NSHTTPURLResponse *response;
                
                NSURLRequest *cr = [sessionController requestForPageWithURL:url method:@"POST" cookies:nil];
                [NSURLConnection sendSynchronousRequest:cr returningResponse:&response error:NULL];
                NSArray *cks = [NSHTTPCookie cookiesWithResponseHeaderFields:[response allHeaderFields] forURL:url];
		
		url = [NSURL URLWithString:@"http://www.turmadoaluno.portoseguro.org.br/Agenda.aspx"];
                NSURLRequest *r = [sessionController requestForPageWithURL:url method:@"GET" cookies:cks];
		data = [NSURLConnection sendSynchronousRequest:r returningResponse:&response error:NULL];
		if (data == nil) {
			[self displayFailViewWithTitle:@"Erro de Conexão." text:@"Não pôde-se conectar ao servidor."];
			return;
		}
		[self cacheData:data];
	}
	ElseNotCached(data);

	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];

	NSString *year = [[document firstElementMatchingPath:@"/html/body//span[@id='ContentPlaceHolder1_lblAno2']"] content];
	NSString *clazz = [[document firstElementMatchingPath:@"/html/body//span[@id='ContentPlaceHolder1_lblTurma']"] content];
	if (year == nil || clazz == nil) {
		[self displayFailViewWithTitle:@"Erro de Interpretação." text:@"Erro:LblAno/LblTurma" kReportIssue];
		
		[document release];
		return;
	}
        
        NSLog(@"DID NOT FAIL! YEAR = %@", year);
        if ([year length] >= 33)
                year = [year substringWithRange:NSMakeRange(27, 4)]; // 27=strlen(Turma para o Ano Letivo de)

	[document release];

	[self $performUIBlock:^{
		[$yearLabel setText:year];
		[$classLabel setText:clazz];

		[self displayContentView];
	}];
}

- (void)loadContentView {
	[super loadContentView];
	
	CGFloat height = 100.f;
	UIView *centerView = [[UIView alloc] initWithFrame:CGRectMake(0.f, [$contentView bounds].size.height/2 - height/2, [$contentView bounds].size.width, height)];

	$yearLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.f, 0.f, [centerView bounds].size.width, 40.f)];
	[$yearLabel setBackgroundColor:[UIColor whiteColor]];
	[$yearLabel setTextColor:[UIColor blackColor]];
        [$yearLabel setTextAlignment:NSTextAlignmentCenter];
	[$yearLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:pxtopt(40.f)]];
        [centerView addSubview:$yearLabel];

	$classLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.f, 40.f, [centerView bounds].size.width, 60.f)];
	[$classLabel setBackgroundColor:[UIColor whiteColor]];
	[$classLabel setTextColor:[UIColor blackColor]];
        [$classLabel setTextAlignment:NSTextAlignmentCenter];
	[$classLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:pxtopt(60.f)]];
        [centerView addSubview:$classLabel];

	[$yearLabel release];
	[$classLabel release];
        
        [$contentView addSubview:centerView];
	[centerView release];
}
@end

/* }}} */

/* Zeugnis {{{ */

@implementation ZeugnisSubjectView {
	UILabel *gradeLabel;

	GradeContainer *$recoveryContainer;
	GradeContainer *$firstSecondContainer;
	GradeContainer *$thirdContainer;
	GradeContainer *$annualContainer;
}

- (id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		$recoveryContainer = nil;

		$firstSecondContainer = [[GradeContainer alloc] init];
		[$firstSecondContainer setIsRecovery:YES];
		[$firstSecondContainer setName:@"Recuperação 1º/2º Períodos"];
		[$firstSecondContainer setGrade:@"0.00"];
		[$firstSecondContainer makeValueTen];
		
		$thirdContainer = [[GradeContainer alloc] init];
		[$thirdContainer setIsRecovery:YES];
		[$thirdContainer setName:@"Recuperação 3º Período"];
		[$thirdContainer setGrade:@"0.00"];
		[$thirdContainer makeValueTen];
		
		$annualContainer = [[GradeContainer alloc] init];
		[$annualContainer setIsRecovery:YES];
		[$annualContainer setName:@"Recuperação Anual"];
		[$annualContainer setGrade:@"0.00"];
		[$annualContainer makeValueTen];

		CGRect nameLabelFrame = CGRectMake(5.f, 0.f, ([self bounds].size.width/3)*2, 54.f);
                gradeLabel = [[UILabel alloc] initWithFrame:CGRectMake(nameLabelFrame.size.width + 5.f, 13.f, [self bounds].size.width/3, 27.f)];
		[gradeLabel setBackgroundColor:[UIColor clearColor]];
		[gradeLabel setTextColor:[UIColor blackColor]];
		[[$tableView tableHeaderView] addSubview:gradeLabel];
	}

	return self;
}

- (void)setContainer:(GradeContainer *)container {
	if ($recoveryContainer) [$recoveryContainer release];
	$recoveryContainer = [container copy];
	[$recoveryContainer calculateGradeFromSubgrades];

	[$firstSecondContainer setSuperContainer:[[$recoveryContainer subGradeContainers] objectAtIndex:0]];
	[$thirdContainer setSuperContainer:[[$recoveryContainer subGradeContainers] objectAtIndex:2]];
	[$annualContainer setSuperContainer:$recoveryContainer];

	[super setContainer:container];
}

- (void)setupTableTopGradesWithTableHeaderView:(UIView *)tableHeaderView {
	NSString *gradeTitle = @"Nota: ";
	NSString *averageTitle = @"Média: ";

	NSMutableAttributedString *gradeAttributedString = [[NSMutableAttributedString alloc] initWithString:[gradeTitle stringByAppendingString:[$container grade]]];
	[gradeAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:pxtopt(24.f)] range:NSMakeRange(0, [gradeTitle length])];
	[gradeAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:pxtopt(24.f)] range:NSMakeRange([gradeTitle length], [gradeAttributedString length]-[gradeTitle length])];
	
	NSMutableAttributedString *averageAttributedString = [[NSMutableAttributedString alloc] initWithString:[averageTitle stringByAppendingString:[$container average]]];
	[averageAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:pxtopt(24.f)] range:NSMakeRange(0, [averageTitle length])];
	[averageAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:pxtopt(24.f)] range:NSMakeRange([averageTitle length], [averageAttributedString length]-[averageTitle length])];

	[gradeLabel setAttributedText:gradeAttributedString];
	[gradeAttributedString release];
}

- (NSInteger)cellCount {
	if ($recoveryContainer == nil) return 0;

	NSInteger ret = 6;
	NSArray *periods = [$recoveryContainer subGradeContainers];

	if (([[[periods objectAtIndex:0] grade] isEqualToString:@"$NoGrade"] || [[periods objectAtIndex:0] isAboveAverage]) &&
	    ([[[periods objectAtIndex:1] grade] isEqualToString:@"$NoGrade"] || [[periods objectAtIndex:1] isAboveAverage]))
		ret--;
	
	// We show R3 only if we don't get RCA.
	if ([[[periods objectAtIndex:2] grade] isEqualToString:@"$NoGrade"] || [[periods objectAtIndex:2] isAboveAverage] || [self recoveredGrades] < kPortoAverage/10)
		ret--;
	
	BOOL isComplete = YES;
	for (GradeContainer *c in periods) { if ([[c grade] isEqualToString:@"$NoGrade"]) { isComplete = NO; break; } }
	if ([self recoveredGrades] >= kPortoAverage/10 || !isComplete)
		ret--;
	
	return ret;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [super numberOfSectionsInTableView:tableView] + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section < [tableView numberOfSections]-1) return [super tableView:tableView numberOfRowsInSection:section];
	return [self cellCount];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([indexPath section] < [tableView numberOfSections]-1) return [super tableView:tableView cellForRowAtIndexPath:indexPath];

	static NSString *cellIdentifier = @"PortoAppRecoveryViewCellIdentifier";
	
	RecoveryTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
	if (cell == nil) {
		cell = [[[RecoveryTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
		[cell setSelectionStyle:UITableViewCellSelectionStyleNone];
		[cell setDelegate:self];
	}
	
	NSArray *periods = [$recoveryContainer subGradeContainers];
	
	GradeContainer *container;
	GradeContainer *backupContainer = nil;
	switch ([indexPath row]) {
		case 0:
			container = [periods objectAtIndex:0];
			backupContainer = [[$container subGradeContainers] objectAtIndex:0];
			break;
		case 1:
			container = [periods objectAtIndex:1];
			backupContainer = [[$container subGradeContainers] objectAtIndex:1];
			break;
		case 2: {
			if (([[[periods objectAtIndex:0] grade] isEqualToString:@"$NoGrade"] || [[periods objectAtIndex:0] isAboveAverage]) &&
			    ([[[periods objectAtIndex:1] grade] isEqualToString:@"$NoGrade"] || [[periods objectAtIndex:1] isAboveAverage])) {
				container = [periods objectAtIndex:2];
				backupContainer = [[$container subGradeContainers] objectAtIndex:2];
                        }
			else {
				container = $firstSecondContainer;
			}

			break;
		}
		case 3:
			if (([[[periods objectAtIndex:0] grade] isEqualToString:@"$NoGrade"] || [[periods objectAtIndex:0] isAboveAverage]) &&
			    ([[[periods objectAtIndex:1] grade] isEqualToString:@"$NoGrade"] || [[periods objectAtIndex:1] isAboveAverage]))
				container = [self recoveredGrades]>kPortoAverage/10 ? $thirdContainer : $annualContainer;
			else {
				container = [periods objectAtIndex:2];
				backupContainer = [[$container subGradeContainers] objectAtIndex:2];
			}
			break;
		case 4:
			container = [self recoveredGrades]>kPortoAverage/10 ? $thirdContainer : $annualContainer;
			break;
                default:
                        container = nil;
                        break;
	}

	[cell setTopText:[container name]];
	[cell setRightText:[self rightTextForContainer:container]];
	[cell setBottomText:![container isRecovery] ? nil : [self recoveryTextForContainer:container]];
	[cell setContainer:container];
	[cell setBackupContainer:backupContainer];

	[cell setNeedsDisplay];
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([indexPath section] < [tableView numberOfSections]-1) return [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 56.f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section < [tableView numberOfSections]-1) return [super tableView:tableView heightForHeaderInSection:section];
	return 2.f;
}

// TODO: UITableViewHeaderFooterView is iOS6+. I dislike having to rely on apis > iOS 5. :(
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section < [tableView numberOfSections]-1) return [super tableView:tableView viewForHeaderInSection:section];

	UIView *v = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
	[v setBackgroundColor:[UIColor grayColor]];
	return v;
}

- (NSString *)recoveryTextForContainer:(GradeContainer *)container {
	// Handle RCA
	if ([container superContainer] == $recoveryContainer) {
		CGFloat recoveredValue = ([self recoveredGrades] + [[container grade] floatValue])/2;
		return [NSString stringWithFormat:@"Nota: %.2f", recoveredValue > kPortoAverage/10 ? kPortoAverage/10 : roundf(recoveredValue*2)/2];
	}
	
	// Handle RC
	// As of 27/3/2014, I love Carla.
	else if ([[container superContainer] weight] == 1) {
		GradeContainer *firstPeriodContainer = [[$recoveryContainer subGradeContainers] objectAtIndex:0];
		GradeContainer *secondPeriodContainer = [[$recoveryContainer subGradeContainers] objectAtIndex:1];
		
		CGFloat firstPeriodGrade = ([[firstPeriodContainer grade] floatValue] + [[container grade] floatValue])/2;
		CGFloat secondPeriodGrade = ([[secondPeriodContainer grade] floatValue] + [[container grade] floatValue])/2;
		if (firstPeriodGrade > kPortoAverage/10) firstPeriodGrade = kPortoAverage/10;
		if (secondPeriodGrade > kPortoAverage/10) secondPeriodGrade = kPortoAverage/10;

		if ([[firstPeriodContainer grade] floatValue] < kPortoAverage/10 && [[secondPeriodContainer grade] floatValue] < kPortoAverage/10) {
			return [NSString stringWithFormat:@"Nota 1ºP: %.2f\tNota 2ºP: %.2f", firstPeriodGrade, secondPeriodGrade];
		}
		else {
			NSString *compulsory;
			if ([[[[$recoveryContainer subGradeContainers] objectAtIndex:0] grade] floatValue] + [[[[$recoveryContainer subGradeContainers] objectAtIndex:1] grade] floatValue]*2 < kPortoAverage/10 + (kPortoAverage/10)*2)
				compulsory = @"(Obrigatório)";
			else
				compulsory = @"(Opcional)";

			if ([[firstPeriodContainer grade] floatValue] < kPortoAverage/10) {
				return [NSString stringWithFormat:@"%@ Nota 1º Período: %.2f", compulsory, firstPeriodGrade];
			}
			else if ([[secondPeriodContainer grade] floatValue] < kPortoAverage/10) {
				return [NSString stringWithFormat:@"%@ Nota 2º Período: %.2f", compulsory, secondPeriodGrade];
			}
		}

		return @"RC_ERROR2 Reportar para q@theiostream.com";
	}
	
	// Handle R3
	else if ([[container superContainer] weight] == 3) {
		CGFloat recoveredValue = ([[[container superContainer] grade] floatValue] + [[container grade] floatValue])/2;
		return [NSString stringWithFormat:@"Nota: %.2f", recoveredValue > kPortoAverage/10 ? kPortoAverage/10 : recoveredValue];
	}

	return @"RC_ERROR1 Reportar para q@theiostream.com";
}

- (NSString *)rightTextForContainer:(GradeContainer *)container {
	NSString *str = @"";

	if (![container isRecovery])
		str = [container isAboveAverage] ? @"AP" : [container weight]==3 ? ([self recoveredGrades]>kPortoAverage/10 ? @"R3" : @"RCA") : @"RC";
	return [str stringByAppendingString:[@"\n" stringByAppendingString:[container grade]]];
}

- (CGFloat)recoveredGrades {
	CGFloat totalGrade = 0.f;
	CGFloat periodGrade, recoveredGrade;

	periodGrade = [[[[$recoveryContainer subGradeContainers] objectAtIndex:0] grade] floatValue];
	if (periodGrade < kPortoAverage/10) {
		recoveredGrade = (periodGrade + [[$firstSecondContainer grade] floatValue])/2;
		if (recoveredGrade < periodGrade) recoveredGrade = periodGrade;
		periodGrade = recoveredGrade > kPortoAverage/10 ? kPortoAverage/10 : recoveredGrade;
	}
	totalGrade += periodGrade;

	periodGrade = [[[[$recoveryContainer subGradeContainers] objectAtIndex:1] grade] floatValue];
	if (periodGrade < kPortoAverage/10) {
		recoveredGrade = (periodGrade + [[$firstSecondContainer grade] floatValue])/2;
		if (recoveredGrade < periodGrade) recoveredGrade = periodGrade;
		periodGrade = recoveredGrade > kPortoAverage/10 ? kPortoAverage/10 : recoveredGrade;
	}
	totalGrade += periodGrade * [[[$recoveryContainer subGradeContainers] objectAtIndex:1] weight];

	periodGrade = [[[[$recoveryContainer subGradeContainers] objectAtIndex:2] grade] floatValue];
	if (periodGrade < kPortoAverage/10 && (periodGrade+totalGrade)/6 > kPortoAverage/10) {
		recoveredGrade = (periodGrade + [[$thirdContainer grade] floatValue])/2;
		if (recoveredGrade < periodGrade) recoveredGrade = periodGrade;
		periodGrade = recoveredGrade > kPortoAverage/10 ? kPortoAverage/10 : recoveredGrade;
	}
	totalGrade += periodGrade * [[[$recoveryContainer subGradeContainers] objectAtIndex:2] weight];
	
	return totalGrade / [$recoveryContainer totalWeight];
}

// FIXME: Don't reload data every time there's a value change; that's too consuming.
// Should instead see when a change is necessary.
- (void)sliderValueChangedForRecoveryCell:(RecoveryTableViewCell *)cell {
	[[cell container] setGrade:[NSString stringWithFormat:@"%.2f", [[cell slider] value]*10]];
	[$recoveryContainer calculateGradeFromSubgrades];
	
	[$tableView reloadData];
}

- (void)dealloc {
	[gradeLabel release];

	[$recoveryContainer release];
	[$firstSecondContainer release];
	[$thirdContainer release];
	[$annualContainer release];

	[super dealloc];
}
@end

@implementation ZeugnisListViewController
- (id)initWithIdentifier:(NSString *)identifier cacheIdentifier:(NSString *)cacheIdentifier postKeys:(NSDictionary *)dict cookies:(NSArray *)cookies {
	if ((self = [super initWithIdentifier:identifier cacheIdentifier:cacheIdentifier])) {
		$postKeys = [dict retain];
		$cookies = [cookies retain];

		$rootContainer = nil;
	}
        
        return self;
}

- (void)$notificationRefresh:(NSNotification *)notification {
	[[self navigationController] popToRootViewControllerAnimated:YES];
	[super $notificationRefresh:notification];
}

- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor whiteColor]];
}

// FIXME: Implement showing frequency in the cell instead of an average N/A; aka stop being lazy and code a special Zeugnis SubjectView cell.
- (void)reloadData {
	if ($rootContainer != nil) {
		[$rootContainer release];
	}
	[self $performUIBlock:^{
		[[$contentView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	}];

	NSData *data;
	IfNotCached {
		SessionController *sessionController = [SessionController sharedInstance];
		
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://notastrimestrais.portoseguro.org.br/NotasTrimestrais.aspx?%@", NSDictionaryURLEncode($postKeys)]];
		NSURLRequest *request = [sessionController requestForPageWithURL:url method:@"POST" cookies:$cookies];
		
		NSURLResponse *response;
		data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:NULL];
		if (data == nil) {
			[self displayFailViewWithTitle:@"Erro de conexão." text:@"Não foi possível uma conexão à Internet."];
			return;
		}
		
		NSURLRequest *boletimRequest = [sessionController requestForPageWithURL:[NSURL URLWithString:@"http://notastrimestrais.portoseguro.org.br/Boletim.aspx"] method:@"GET" cookies:$cookies];
		data = [NSURLConnection sendSynchronousRequest:boletimRequest returningResponse:&response error:NULL];
		if (data == nil) {
			[self displayFailViewWithTitle:@"Erro de conexão." text:@"Não foi possível uma conexão à Internet."];
			return;
		}
		
		[self cacheData:data];
	}
	ElseNotCached(data);
	
	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
	
	$rootContainer = [[GradeContainer alloc] init];
	[$rootContainer setDebugLevel:0];
	[$rootContainer makeValueTen];
	[$rootContainer setIsBonus:NO];
	[$rootContainer setName:@"Total"];
	[$rootContainer setWeight:1];

	NSMutableArray *containers = [NSMutableArray array];
	
	NSArray *tableElements_ = [[document firstElementMatchingPath:@"/html/body//table[@id='gridBoletim']"] elementsMatchingPath:@"./tr"];
	if ([tableElements_ count] == 1) {
		if ([[[[tableElements_ objectAtIndex:0] firstElementMatchingPath:@"./td/h3"] content] isEqualToString:kNoZeugnisMessage])
			[self displayFailViewWithTitle:@"Boletim Não Encontrado" text:@"Não há um boletim disponível para o ano selecionado."];
		else
			[self displayFailViewWithTitle:@"Erro de interpretação" text:@"Erro:XML:GridBoletim" @kReportIssue];
		
		[document release];
		return;
	}

	// We remove the first two elements (table headers) and the last three (Ano Letivo/Dias Letivos, Observações, Information)
	NSArray *tableElements = [tableElements_ subarrayWithRange:NSMakeRange(2, [tableElements_ count]-5)];
	for (XMLElement *tr in tableElements) {
		NSArray *tdElements = [tr elementsMatchingPath:@"./td"];
		NSString *subjectName = [[tdElements objectAtIndex:0] content];
		if ([subjectName isEqualToString:@"EDUCAÇÃO FÍSICA"]) continue; // No grades.
		
		if ([subjectName hasPrefix:@"*"]) {
			subjectName = [[subjectName substringFromIndex:1] substringToIndex:[subjectName length]-2];
			subjectName = [subjectName stringByAppendingString:@" \ue50e"]; // \ue50e is meant to be a DE flag.
		}
		
		NSString *firstGrade = [[[tdElements objectAtIndex:1] content] americanFloat];
		NSString *secondGrade = [[[tdElements objectAtIndex:4] content] americanFloat];
		NSString *thirdGrade = [[[tdElements objectAtIndex:7] content] americanFloat];
		NSString *finalGrade = [[[tdElements objectAtIndex:14] content] americanFloat];
		
                if ([firstGrade isEqualToString:@" "]) firstGrade = @"$NoGrade";
		if ([secondGrade isEqualToString:@" "]) secondGrade = @"$NoGrade";
		if ([thirdGrade isEqualToString:@" "]) thirdGrade = @"$NoGrade";
		if ([finalGrade isEqualToString:@" "]) finalGrade = @"$NoGrade";
                
		NSArray *periods = [NSArray arrayWithObjects:firstGrade, secondGrade, thirdGrade, nil];
		NSArray *order = [NSArray arrayWithObjects:@"Primeiro", @"Segundo", @"Terceiro", nil];

		GradeContainer *subContainer = [[[GradeContainer alloc] init] autorelease];
		[subContainer setDebugLevel:1];
		[subContainer makeValueTen];
		[subContainer setIsBonus:NO];
		[subContainer setName:subjectName];
		[subContainer setWeight:1];
		[subContainer setGrade:finalGrade];
		[subContainer setAverage:@"$NoGrade"];
		[subContainer setSuperContainer:$rootContainer];
		
		NSMutableArray *subContainers = [NSMutableArray array];
		for (NSInteger i=0; i<[periods count]; i++) {
			GradeContainer *subsubContainer = [[[GradeContainer alloc] init] autorelease];
			[subsubContainer setDebugLevel:2];
			[subsubContainer makeValueTen];
			[subsubContainer setIsBonus:NO];
			[subsubContainer setShowsGraph:NO];
			[subsubContainer setName:[[order objectAtIndex:i] stringByAppendingString:@" Período"]];
			// Here we assume that period 1 has weight 1, 2 has weight 2 and so on.
			// If this ever changes, we'll need some constants.
			[subsubContainer setWeight:i+1];
			[subsubContainer setGrade:[periods objectAtIndex:i]];
			[subsubContainer setAverage:@"$NoGrade"];
			[subsubContainer setSuperContainer:subContainer];

			[subContainers addObject:subsubContainer];
		}
		[subContainer setSubGradeContainers:subContainers];
		[containers addObject:subContainer];
	}
	[$rootContainer setSubGradeContainers:containers];

	[self $performUIBlock:^{
		[(UICollectionView *)$contentView reloadData];
		[self displayContentView];
	}];

	[document release];
}

- (void)loadContentView {
	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	[layout setScrollDirection:UICollectionViewScrollDirectionHorizontal];

	UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:[self contentViewFrame] collectionViewLayout:layout];
	[layout release];

	[collectionView setDataSource:self];
	[collectionView setDelegate:self];
	[collectionView registerClass:[ZeugnisSubjectView class] forCellWithReuseIdentifier:@"ZeugnisSubjectViewIdentifier"];
	[collectionView setBackgroundColor:[UIColor whiteColor]];
	[collectionView setScrollsToTop:NO];
	[collectionView setPagingEnabled:YES];

	$contentView = collectionView;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	if ($rootContainer == nil) return 0;
	return [[$rootContainer subGradeContainers] count];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return 1;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	return [collectionView bounds].size;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	ZeugnisSubjectView *cell = (ZeugnisSubjectView *)[collectionView dequeueReusableCellWithReuseIdentifier:@"ZeugnisSubjectViewIdentifier" forIndexPath:indexPath];
	[cell setContainer:[[$rootContainer subGradeContainers] objectAtIndex:[indexPath section]]];

	return cell;
}

/*- (void)prepareContentView {
	NoButtonDelayScrollView *contentView = (NoButtonDelayScrollView *)$contentView;
	NSArray *subjectContainers = [$rootContainer subGradeContainers];

	CGRect subviewRect = CGRectMake(0.f, 0.f, [contentView bounds].size.width, [contentView bounds].size.height);
	for (GradeContainer *subject in subjectContainers) {
		ZeugnisSubjectView *subjectView = [[[ZeugnisSubjectView alloc] initWithFrame:subviewRect container:subject] autorelease];
		[contentView addSubview:subjectView];

		subviewRect.origin.x += subviewRect.size.width;
	}
	[contentView setContentSize:CGSizeMake(subviewRect.origin.x, [contentView bounds].size.height)];
}*/

- (void)dealloc {
	[$postKeys release];
	[$cookies release];

	[$rootContainer release];

	[super dealloc];
}
@end

@implementation ZeugnisViewController
- (NSString *)serviceName {
	return @"Boletim";
}

- (id)initWithIdentifier:(NSString *)identifier {
	if ((self = [super initWithIdentifier:identifier])) {
		$yearOptions = [[NSMutableArray alloc] init];
		
		$viewState = nil;
		$eventValidation = nil;
		$cookies = nil;
	}

	return self;
}

- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor whiteColor]];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:[self serviceName]];
}

- (void)reloadData {
	[$yearOptions removeAllObjects];
	if ($cookies != nil) { [$cookies release]; $cookies = nil; }
	if ($viewState != nil) { [$viewState release]; $viewState = nil; }
	if ($eventValidation != nil) { [$eventValidation release]; $eventValidation = nil; }

	SessionController *sessionController = [SessionController sharedInstance];
	if (![sessionController gradeID]) {
		[sessionController generateGradeID];
		if (![sessionController gradeID]) {
			[self displayFailViewWithTitle:@"Sem ID de Notas." text:@kReportIssue];
			return;
		}
	}
	
	NSData *data;
	IfNotCached {
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://notastrimestrais.portoseguro.org.br/NotasTrimestrais.aspx?token=%@", [sessionController gradeID]]];
		NSHTTPURLResponse *response;
		data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:NULL];
		if (data == nil) {
			[self displayFailViewWithTitle:@"Erro de conexão." text:@"Não foi possível uma conexão à Internet."];
			return;
		}
		[self cacheData:data];

		$cookies = [[NSHTTPCookie cookiesWithResponseHeaderFields:[response allHeaderFields] forURL:[response URL]] retain];
	}
	ElseNotCached(data);

	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
	
	$viewState = [[[[document firstElementMatchingPath:@"/html/body//input[@id='__VIEWSTATE']"] attributes] objectForKey:@"value"] retain];
	$eventValidation = [[[[document firstElementMatchingPath:@"/html/body//input[@id='__EVENTVALIDATION']"] attributes] objectForKey:@"value"] retain];

	XMLElement *select = [document firstElementMatchingPath:@"/html/body//select[@id='ddlAno']"];
	NSArray *options = [select elementsMatchingPath:@"./option"];
	for (XMLElement *option in options) {
		Pair *p = [[[Pair alloc] initWithObjects:[option content], [[option attributes] objectForKey:@"value"]] autorelease];
		[$yearOptions addObject:p];
	}

        [document release];

	[self $performUIBlock:^{
		UITableView *tableView = (UITableView *)$contentView;
		[tableView reloadData];

		[self displayContentView];
	}];
}

- (void)loadContentView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:[self contentViewFrame] style:UITableViewStylePlain];
	[tableView setDataSource:self];
	[tableView setDelegate:self];

	$contentView = tableView;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [$yearOptions count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PortoAppZeugnisViewControllerCell"];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PortoAppZeugnisViewControllerCell"] autorelease];
		[cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
	}
	
	Pair *yearValue_ = [$yearOptions objectAtIndex:[indexPath row]];
	NSString *year = (NSString *)yearValue_->obj1;
	[[cell textLabel] setText:year];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	// This is here to avoid something like
	// Loads cached boletim list, then shouldn't cache anymore, then cookies kept are nil, then won't be able to load the Boletim which won't be cached either.
	if ($cookies == nil && ![self shouldUseCachedData]) {
		AlertError(@"Não Há Cookies", @"Por favor recarregue a página.");
		return;
	}

	Pair *yearValue_ = [$yearOptions objectAtIndex:[indexPath row]];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
		yearValue_->obj2, @"ddlAno",
		$viewState, @"__VIEWSTATE",
		$eventValidation, @"__EVENTVALIDATION",
		@"UpdatePanel1%7CbtVisualizar", @"ScriptManager1", // do we need this key?
		@"Visualizar", @"btVisualizar",
		nil];

	ZeugnisListViewController *listController = [[[ZeugnisListViewController alloc] initWithIdentifier:@"zeugnislist" cacheIdentifier:yearValue_->obj2 postKeys:dict cookies:$cookies] autorelease];
	[listController setTitle:yearValue_->obj1];
	[[self navigationController] pushViewController:listController animated:YES];

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)dealloc {
	[$yearOptions release];
	
        if ($viewState != nil) [$viewState release];
        if ($eventValidation != nil) [$eventValidation release];
        if ($cookies != nil) [$cookies release];
	
        [super dealloc];
}
@end

/* }}} */

/* Photo {{{ */

@implementation PhotoViewController
- (NSString *)serviceName {
	return @"Foto do Aluno";
}

- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor whiteColor]];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:[self serviceName]];
}

- (void)reloadData {
	//[super reloadData];
	
	[(UIImageView *)[[self contentView] viewWithTag:55] setImage:nil];
	
	NSData *imageData;
	IfNotCached {
		SessionController *sessionController = [SessionController sharedInstance];
		if (![sessionController hasSession]) {
			[self displayFailViewWithTitle:@"Sem autenticação" text:@"Realize o login no menu de Contas."];
			return;
		}
		if (![sessionController gradeID]) {
			[sessionController generateGradeID]; // it doesn't cost to try...
			if (![sessionController gradeID]) {
				[self displayFailViewWithTitle:@"Sem ID de Notas" text:@kReportIssue];
				return;
			}
		}
		
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://notasparciais.portoseguro.org.br/notasparciais.aspx?token=%@", [sessionController gradeID]]];
		NSURLResponse *response;
		NSData *data = [sessionController loadPageWithURL:url method:@"POST" response:&response error:NULL];
		if (data == nil) {
			[self displayFailViewWithTitle:@"Falha ao carregar página." text:@"Cheque sua conexão de Internet."];
			return;
		}
		
		XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
		XMLElement *imgTag = [document firstElementMatchingPath:@"//img[@id='ContentPlaceHolder1_imgFotoAluno']"];
		
		if (imgTag == nil) {
			[self displayFailViewWithTitle:@"Falha de Interpretação." text:@"Erro: ImgElement" kReportIssue];
			[document release];
			return;
		}

		imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[@"http://notasparciais.portoseguro.org.br/" stringByAppendingString:[[imgTag attributes] objectForKey:@"src"]]]];
		[self cacheData:imageData];

		[document release];
	}
	ElseNotCached(imageData);
	
	[self $performUIBlock:^{
		UIImageView *imageView = (UIImageView *)[self contentView];
		[imageView setImage:[UIImage imageWithData:imageData]];

		[self displayContentView];
	}];
}

- (void)loadContentView {
	UIImageView *imageView = [[UIImageView alloc] initWithFrame:[self contentViewFrame]];

	$contentView = imageView;
}
@end

/* }}} */

/* }}} */

/* Services {{{ */

@implementation ServicesViewController
- (id)init {
	if ((self = [super init])) {
		$customLinks = [[NSMutableArray alloc] init];
		
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[$customLinks addObjectsFromArray:[defaults arrayForKey:@"ServicesCustomURL"]];
	}

	return self;
}

- (void)loadView {
	[super loadView];
	
	ClassViewController *classController = [[ClassViewController alloc] initWithIdentifier:@"classservice"];
	ZeugnisViewController *zeugnisController = [[ZeugnisViewController alloc] initWithIdentifier:@"zeugnisservice"];
	PhotoViewController *photoController = [[PhotoViewController alloc] initWithIdentifier:@"photoservice"];

	$controllers = [[NSArray alloc] initWithObjects:
		classController,
		zeugnisController,
		photoController,
		nil];
	
	[classController release];
	[zeugnisController release];
	[photoController release];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	[self setTitle:@"Serviços"];

	UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addLink:)];
	[[self navigationItem] setRightBarButtonItem:addButton];
	[addButton release];
}

- (void)addLink:(id)sender {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Adicionar Link" message:@"Insira o título e URL para o link desejado." delegate:self cancelButtonTitle:@"Cancelar" otherButtonTitles:@"OK", nil];
	[alert setAlertViewStyle:UIAlertViewStyleLoginAndPasswordInput];
	
	[[alert textFieldAtIndex:0] setPlaceholder:@"Título do Link"];
	[[alert textFieldAtIndex:1] setPlaceholder:@"URL do Link"];
	[[alert textFieldAtIndex:1] setSecureTextEntry:NO];
	[[alert textFieldAtIndex:1] setDelegate:self];

	[alert show];
	[alert release];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
	[textField setText:@"http://"];
}

// FIXME: Somehow check the validity of created links.
// An alternative would be to show the erroneous link in the fail view.
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex != [alertView cancelButtonIndex]) {
		[$customLinks addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			[[alertView textFieldAtIndex:0] text], @"LinkTitle",
			[[alertView textFieldAtIndex:1] text], @"LinkURL",
			nil]];

		[[NSUserDefaults standardUserDefaults] setObject:$customLinks forKey:@"ServicesCustomURL"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[[self tableView] reloadData];
	}
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [$customLinks count] > 0 ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
        return section==0 ? [$controllers count] : [$customLinks count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section==0 ? @"Serviços" : @"Links";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PortoAppServicesCellIdentifier"];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PortoAppServicesCellIdentifier"] autorelease];
		[cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
	}
	
	[[cell textLabel] setText:[indexPath section]==0 ? [[$controllers objectAtIndex:[indexPath row]] serviceName] : [[$customLinks objectAtIndex:[indexPath row]] objectForKey:@"LinkTitle"]];
	
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return [indexPath section] == 1;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		[$customLinks removeObjectAtIndex:[indexPath row]];
		[[NSUserDefaults standardUserDefaults] setObject:$customLinks forKey:@"ServicesCustomURL"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		
                // TODO: Find a way to make this weirdfuck animation decent.
		[tableView reloadData];
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([indexPath section] == 0) {
		[[self navigationController] pushViewController:[$controllers objectAtIndex:[indexPath row]] animated:YES];
	}
	else {
		NSURLRequest *request = [[SessionController sharedInstance] requestForPageWithURL:[NSURL URLWithString:[[$customLinks objectAtIndex:[indexPath row]] objectForKey:@"LinkURL"]] method:@"GET"];
		NSLog(@"%@", [NSURL URLWithString:[[$customLinks objectAtIndex:[indexPath row]] objectForKey:@"LinkURL"]]);

		WebViewController *controller = [[WebViewController alloc] init];
		[controller loadRequest:request];
		
		[[self navigationController] pushViewController:controller animated:YES];
		[controller release];
	}
	
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)dealloc {
	[$controllers release];
	[$customLinks release];

	[super dealloc];
}
@end

/* }}} */

/* }}} */

/* Account Controller {{{ */

// TODO: Rethink whether we should use the login data as the table header view or as a "Login" section's header view.
static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info);
@implementation AccountViewController
- (id)init {
	if ((self = [super init])) {
		$isLoggingIn = NO;
		
		$reachability = SCNetworkReachabilityCreateWithName(NULL, "www.educacional.com.br");
		SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
		if (!SCNetworkReachabilitySetCallback($reachability, ReachabilityCallback, &context)) {
			CFRelease($reachability);
			$reachability = NULL;
		}
	}

	return self;
}

- (void)loadView {
	UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
	[tableView setDelegate:self];
	[tableView setDataSource:self];
	[self setTableView:tableView];
	[tableView release];

	$infoView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, [[UIScreen mainScreen] bounds].size.width, 85.f)];
	
	/*UIFont *boldFont = [UIFont boldSystemFontOfSize:15.f];
	UIFont *normalFont = [UIFont systemFontOfSize:13.f];*/

	UILabel *usernameLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.f, 10.f, [$infoView bounds].size.width-40.f, 25.f)];
	[usernameLabel setFont:[UIFont boldSystemFontOfSize:pxtopt([usernameLabel bounds].size.height)]];
	[usernameLabel setTextColor:[UIColor blackColor]];
	[usernameLabel setBackgroundColor:[UIColor clearColor]];
	[usernameLabel setTag:87];
	[$infoView addSubview:usernameLabel];
	[usernameLabel release];

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.f, [usernameLabel frame].origin.y + [usernameLabel bounds].size.height + 2.f, [$infoView bounds].size.width-40.f, 20.f)];
	[nameLabel setFont:[UIFont systemFontOfSize:pxtopt([nameLabel bounds].size.height)]];
	[nameLabel setTextColor:[UIColor grayColor]];
	[nameLabel setBackgroundColor:[UIColor clearColor]];
	[nameLabel setTag:88];
	[$infoView addSubview:nameLabel];
	[nameLabel release];

	UILabel *gradeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.f, [nameLabel frame].origin.y + [nameLabel bounds].size.height - 2.f, [$infoView bounds].size.width-40.f, 20.f)];
	[gradeLabel setFont:[UIFont systemFontOfSize:pxtopt([gradeLabel bounds].size.height)]];
	[gradeLabel setTextColor:[UIColor grayColor]];
	[gradeLabel setBackgroundColor:[UIColor clearColor]];
	[gradeLabel setTag:89];
	[$infoView addSubview:gradeLabel];
	[gradeLabel release];

	$loginOutCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[[$loginOutCell textLabel] setTextAlignment:NSTextAlignmentCenter];

	$aboutCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[$aboutCell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
	[[$aboutCell textLabel] setText:@"Sobre o app"];

	$theiostreamCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	[$theiostreamCell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
	[[$theiostreamCell textLabel] setText:@"Sobre o desenvolvedor"];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	[self setTitle:@"Conta"];
	[self reloadData];
}

// TODO: Implement a timer so we don't get troubled by small 3G usage stuff.
static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
	NSLog(@"REACHABILITY CALLBACK: %@", (id)info);
	AccountViewController *self = (AccountViewController *)info;

	NetworkStatus status = NotReachable;
	if ((flags & kSCNetworkReachabilityFlagsReachable) != 0) {
		if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
			status = ReachableViaWiFi;
		}
		
		if ((((flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0) ||
		      (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0)) {
			if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
				status = ReachableViaWiFi;
			}
		}

		if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
			status = ReachableViaWWAN;
		}
	}
	
	NSLog(@"CONNECTED: %d (st=%d)", status != NotReachable, status);
	if (status != NotReachable) {
		NSLog(@"REACHABLE NOW");
		if ([[SessionController sharedInstance] hasAccount] && ![[SessionController sharedInstance] hasSession]) {
			NSLog(@"PERFORM LOGIN");
			[self performLogin];
			[self reloadData];
		}
	}
	else if (self->$isLoggingIn) {
		NSLog(@"IS LOGGING IN AND SUFFERED CALLBACK");
		AlertError(@"Erro de login", @"Falha na conexão");

		self->$isLoggingIn = NO;
		[self reloadData];
	}
	else if ([[SessionController sharedInstance] hasSession]) {
		NSLog(@"NOT CONNETED, HAS SESSION, LOGOUT");
		[[SessionController sharedInstance] setSessionInfo:nil];
		[self reloadData];
	}
}

- (void)viewDidAppear:(BOOL)animated {
	if ($reachability != NULL)
		SCNetworkReachabilityScheduleWithRunLoop($reachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (void)viewWillDisappear:(BOOL)animated {
	if ($reachability != NULL)
		SCNetworkReachabilityUnscheduleFromRunLoop($reachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section==1 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section==1 ? @"Informações" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [indexPath section]==0 ? $loginOutCell : [indexPath row]==0 ? $aboutCell : $theiostreamCell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([indexPath section] == 0) {
		if ($isLoggingIn) return;

		SessionController *sessionController = [SessionController sharedInstance];
		if ([sessionController hasSession]) {
			[sessionController unloadSession];
			[sessionController setAccountInfo:nil];
			
			[self reloadData];
		}
		else if ([sessionController hasAccount]) {
			[self performLogin];
		}
		else {
                        [self popupLoginController];
		}
	}

	else {
		if ([indexPath row] == 0) {
			WebViewController *aboutController = [[WebViewController alloc] init];
			[aboutController loadLocalFile:[[NSBundle mainBundle] pathForResource:@"about" ofType:@"html"]];

			[[self navigationController] pushViewController:aboutController animated:YES];
			[aboutController release];
		}
		else {
			WebViewController *theiostreamController = [[WebViewController alloc] init];
			[theiostreamController loadLocalFile:[[NSBundle mainBundle] pathForResource:@"theiostream" ofType:@"html"]];
			
			[[self navigationController] pushViewController:theiostreamController animated:YES];
			[theiostreamController release];
		}
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)performLogin {
	SessionController *sessionController = [SessionController sharedInstance];
	[sessionController loadSessionWithHandler:^(BOOL success, NSError *error){
		if (!success) {
			if ([[error domain] isEqualToString:kPortoErrorDomain]) {
				if ([error code] == -1) {
                                        AlertError(@"Erro de Login", @"Não se pôde conectar ao servidor.");
                                }
                                else if ([error code] == 1) {
                                        AlertError(@"Erro de Login", @"O login ou senha encontram-se incorretos.");
                                        [sessionController setAccountInfo:nil];
                                }
                                else {
                                        NSLog(@"PORTO ERROR %d", [error code]);
					AlertError(@"Erro de Login", @"Erro inesperado.");
                                }
                        }
                }
	
                $isLoggingIn = NO;
                [self reloadData];
        }];

	$isLoggingIn = YES;
	[self reloadData];
}

- (void)popupLoginController {
	PortoLoginController *loginController = [[PortoLoginController alloc] init];
	[loginController setDelegate:self];
	
	UINavigationController *navLoginController = [[[UINavigationController alloc] initWithRootViewController:loginController] autorelease];
	[self presentViewController:navLoginController animated:YES completion:NULL];
	[loginController release];
}

- (void)loginControllerDidLogin:(LoginController *)controller {
	[self reloadData];
	[self dismissViewControllerAnimated:YES completion:NULL];
}

static inline NSString *GetGenderUnicode(NSString *genderCookie) {
	return [genderCookie isEqualToString:@"M"] ? @" \u2642" : @" \u2640";
}
static inline NSString *GetDecentName(NSString *nameCookie) {
	NSMutableString *spaced = [[[[nameCookie stringByReplacingOccurrencesOfString:@"+" withString:@" "] lowercaseString] mutableCopy] autorelease];
	[spaced replaceCharactersInRange:NSMakeRange(0, 1) withString:[[spaced substringWithRange:NSMakeRange(0, 1)] capitalizedString]];

	NSRange range = NSMakeRange(0, [spaced length]);
	while (range.location != NSNotFound) {
		range = [spaced rangeOfString:@" " options:0 range:range];
		if (range.location != NSNotFound) {
			[spaced replaceCharactersInRange:NSMakeRange(range.location+1, 1) withString:[[spaced substringWithRange:NSMakeRange(range.location+1, 1)] capitalizedString]];
			range = NSMakeRange(range.location + range.length, [spaced length] - (range.location + range.length));
		}
	}

	return spaced;
}
static inline NSString *GetDecentGrade(NSString *gradeCookie) {
	// For Educação Infantil, I have no idea what's the format.

	if ([gradeCookie intValue] < 10)
		return [NSString stringWithFormat:@"%d\u00BA Ano do Ensino Fundamental", [gradeCookie intValue]+1];
	else if ([gradeCookie intValue] > 10)
		return [NSString stringWithFormat:@"%d\u00AA Série do Ensino Médio", [gradeCookie intValue]-10];
	
	return [NSString stringWithFormat:@"Série: %@", gradeCookie];
}

- (void)reloadData {
	SessionController *sessionController = [SessionController sharedInstance];
        
        if (!$isLoggingIn)
		[[$loginOutCell textLabel] setText:[sessionController hasSession] ? @"Logout" : @"Login"];
	else
		[[$loginOutCell textLabel] setText:@"Realizando login..."];
	
	if ([sessionController hasSession]) {
		[$infoView setFrame:CGRectMake(0.f, 0.f, [[UIScreen mainScreen] bounds].size.width, 85.f)];
		
		for (UIView *v in [$infoView subviews]) [v setHidden:NO];
		[(UILabel *)[$infoView viewWithTag:87] setText:[[sessionController accountInfo] objectForKey:kPortoUsernameKey]];
		[(UILabel *)[$infoView viewWithTag:88] setText:[GetDecentName([[sessionController sessionInfo] objectForKey:kPortoNameKey]) stringByAppendingString:GetGenderUnicode([[sessionController sessionInfo] objectForKey:kPortoGenderKey])]];
		[(UILabel *)[$infoView viewWithTag:89] setText:GetDecentGrade([[sessionController sessionInfo] objectForKey:kPortoGradeKey])];
	}
	else if ([sessionController accountInfo] != nil) {
		[$infoView setFrame:CGRectMake(0.f, 0.f, [[UIScreen mainScreen] bounds].size.width, 70.f)];
		
		[(UILabel *)[$infoView viewWithTag:87] setHidden:NO];
		[(UILabel *)[$infoView viewWithTag:87] setText:[[sessionController accountInfo] objectForKey:kPortoUsernameKey]];
		[(UILabel *)[$infoView viewWithTag:88] setHidden:NO];
		[(UILabel *)[$infoView viewWithTag:88] setText:@"Não Logado"];
		[(UILabel *)[$infoView viewWithTag:89] setHidden:YES];
	}
	else {
		for (UIView *v in [$infoView subviews]) [v setHidden:YES];
		[$infoView setFrame:CGRectMake(0.f, 0.f, [[UIScreen mainScreen] bounds].size.width, 15.f)];
	}
	
	[[self tableView] setTableHeaderView:nil];
	[[self tableView] setTableHeaderView:$infoView];
}

- (void)loginControllerDidCancel:(LoginController *)controller {
	[self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)dealloc {
	[$infoView release];
	[$loginOutCell release];
	[$aboutCell release];

	if ($reachability != NULL)
		CFRelease($reachability);
	
	[super dealloc];
}
@end

/* }}} */

// Uncomment this function's line to remove authentication information.
static void DebugInit() {
	//[[SessionController sharedInstance] setAccountInfo:nil];
}

/* App Delegate {{{ */

@implementation AppDelegate
@synthesize window = $window;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
	DebugInit();
	
	$window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	[$window setBackgroundColor:[UIColor whiteColor]];

	NewsViewController *newsViewController = [[[NewsViewController alloc] initWithIdentifier:@"news"] autorelease];
	UINavigationController *newsNavController = [[[UINavigationController alloc] initWithRootViewController:newsViewController] autorelease];
	[newsNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notícias" image:_UIImageWithName(@"UITabBarFavoritesTemplate.png") tag:0] autorelease]];
	
	GradesViewController *gradesViewController = [[[GradesViewController alloc] initWithIdentifier:@"grades"] autorelease];
	UINavigationController *gradesNavController = [[[UINavigationController alloc] initWithRootViewController:gradesViewController] autorelease];
	[gradesNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notas" image:/*_UIImageWithName(@"UITabBarMostViewedTemplate.png")*/[UIImage imageNamed:@"grade_tab.png"] tag:0] autorelease]];
	
	PapersViewController *papersViewController = [[[PapersViewController alloc] initWithIdentifier:@"papers"] autorelease];
	UINavigationController *papersNavController = [[[UINavigationController alloc] initWithRootViewController:papersViewController] autorelease];
	[papersNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Circulares" image:_UIImageWithName(@"UITabBarBookmarksTemplate.png") tag:0] autorelease]];

	ServicesViewController *servicesViewController = [[[ServicesViewController alloc] init] autorelease];
	UINavigationController *servicesNavController = [[[UINavigationController alloc] initWithRootViewController:servicesViewController] autorelease];
	[servicesNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Serviços" image:_UIImageWithName(@"UITabBarMoreTemplate.png") tag:0] autorelease]];

	AccountViewController *accountViewController = [[[AccountViewController alloc] init] autorelease];
	UINavigationController *accountNavViewController = [[[UINavigationController alloc] initWithRootViewController:accountViewController] autorelease];
	[accountNavViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Conta" image:_UIImageWithName(@"UITabBarContactsTemplate.png") tag:0] autorelease]];

	NSArray *controllers = [NSArray arrayWithObjects:
		newsNavController,
		gradesNavController,
		papersNavController,
		servicesNavController,
		accountNavViewController,
		nil];
	$tabBarController = [[UITabBarController alloc] init];
	[$tabBarController setViewControllers:controllers];

	if (!SYSTEM_VERSION_GT_EQ(@"7.0"))
		[[UINavigationBar appearance] setTintColor:UIColorFromHexWithAlpha(0x1c2956, 1.f)];

	[$window setRootViewController:$tabBarController];
	[$window makeKeyAndVisible];
	
	accountViewController->$isLoggingIn = YES;
	[accountViewController reloadData];

	[[SessionController sharedInstance] loadSessionWithHandler:^(BOOL success, NSError *error){
		if (success) {
			accountViewController->$isLoggingIn = NO;
			[accountViewController reloadData];

			return;
		}

		if ([[error domain] isEqualToString:kPortoErrorDomain]) {
			if ([error code] == 10) {
				[$tabBarController setSelectedIndex:4];
				[accountViewController popupLoginController];
			}

			else if ([error code] >= 0) {
				UIAlertView *errorAlert = [[UIAlertView alloc] init];
				[errorAlert setTitle:@"Erro"];
				[errorAlert setMessage:[NSString stringWithFormat:@"Erro de login (%d).", [error code]]];
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
		
		accountViewController->$isLoggingIn = NO;
		[accountViewController reloadData];
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
	init_viewstate_context();	

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Well, let's hope this goes unnoticed.
	const char fname_[17] = { 96, 86, 74, 74, 110, 98, 104, 102, 88, 106, 117, 105, 79, 98, 110, 102, '\0' };
	char *fname = decode_derpcipher(fname_);
	*(void **)(&_UIImageWithName) = dlsym(RTLD_DEFAULT, fname);
	free(fname);

	int ret = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    	
	cleanup_viewstate_context();
	[pool drain];
	return ret;
}

/* }}} */

/* }}} */

