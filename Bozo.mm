/* PortoApp
 iOS interface to the Colégio Visconde de Porto Seguro grade/news etc.
 
 Created by Daniel Ferreira in 9/09/2013
 (c) 2013 Bacon Coding Company, LLC
 no rights whatsoever to the Fundação Visconde de Porto Seguro
 
 Licensed under the GNU General Public License version 3.
 */

/* Credits {{{

Personal thanks:
- Dustin Howett
- Guilherme (Lima) Stark
- Max Shavrick
 
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

#include <map>
/* }}} */

/* External {{{ */

#import "External.mm"

/* }}} */

/* Helpers {{{ */

/* URL Encoding {{{ */
static NSString *NSStringURLEncode(NSString *string) {
	return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)string, NULL, CFSTR("!*'();:@&;=+$,/%?#[]"), kCFStringEncodingUTF8) autorelease];
}

static NSString *NSStringURLDecode(NSString *string) {
	return [(NSString *)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL, (CFStringRef)string, CFSTR(""), kCFStringEncodingUTF8) autorelease];
}
/* }}} */

/* Unescaping HTML {{{ */
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

static NSMutableDictionary *cache = nil;
static inline void InitCache() { cache = [[NSMutableDictionary alloc] init]; }
static inline id Cached(NSString *key) { return [cache objectForKey:key]; }
static inline void Cache(NSString *key, id object) { [cache setObject:object forKey:key]; }

/* }}} */

/* Pair {{{ */

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

/* Some history on these functions:
./2013-09-18.txt:[18:11:35] <@theiostream> i'm using coretext
./2013-09-18.txt:[19:23:51] <@theiostream> and Maximus, all made in coretext ;)
./2013-09-18.txt:[19:32:55] <@theiostream> Maximus: coretext doesn't let me
./2013-09-27.txt:[23:14:50] <@theiostream> i need to draw shit with coretext
./2013-09-27.txt:[23:15:03] <@theiostream> since i need to spin the context to draw coretext
./2013-09-27.txt:[23:16:47] <Maximus_> coretext is ok

./2013-09-01.txt:[16:37:47] <@DHowett> fucking coretext
*/

static CFAttributedStringRef CreateBaseAttributedString(CTFontRef font, CGColorRef textColor, CFStringRef string, BOOL underlined, CTLineBreakMode lineBreakMode = kCTLineBreakByWordWrapping, CTTextAlignment alignment = kCTLeftTextAlignment)  {
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
	CFAttributedStringRef attributedString = CreateBaseAttributedString(font, textColor, string, underlined, lineBreakMode);
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

/* }}} */

/* Constants {{{ */

#define kPortoRootURL @"http://www.portoseguro.org.br/"

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
@end

@implementation NSString (AmericanFloat)
- (NSString *)americanFloat {
	return [self stringByReplacingOccurrencesOfString:@"," withString:@"."];
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

	NSDictionary *$accountInfo;
	NSString *$gradeID;
	NSDictionary *$sessionInfo;
}
+ (SessionController *)sharedInstance;

- (NSDictionary *)accountInfo;
- (void)setAccountInfo:(NSDictionary *)secInfo;
- (BOOL)hasAccount;

- (NSString *)gradeID;
- (void)setGradeID:(NSString *)gradeID;

- (NSDictionary *)sessionInfo;
- (void)setSessionInfo:(NSDictionary *)sessionInfo;
- (BOOL)hasSession;

- (void)loadSessionWithHandler:(void(^)(BOOL, NSError *))handler;
- (NSData *)loadPageWithURL:(NSURL *)url method:(NSString *)method response:(NSURLResponse **)response error:(NSError **)error;
@end

/* }}} */

/* Views {{{ */

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

@property(nonatomic, retain) NSArray *subGradeContainers;
@property(nonatomic, retain) GradeContainer *superContainer;

- (NSInteger)totalWeight;
- (BOOL)isAboveAverage;

- (void)makeValueTen;

- (NSString *)gradePercentage;
- (void)calculateGradeFromSubgrades;
- (void)calculateAverageFromSubgrades;
- (NSInteger)indexAtSupercontainer;
- (float)gradeInSupercontainer;

@property(nonatomic, assign) NSInteger debugLevel;
@end

@interface TestView : UIView {
}
@property(nonatomic, retain) GradeContainer *container;
@end

@interface SubjectTableHeaderView : TestView
@end

@interface SubjectTableViewCellContentView : TestView
@end

@interface SubjectGraphView : UIView
@property(nonatomic, retain) GradeContainer *container;
@end

@interface SubjectView : UIView <UITableViewDataSource, UITableViewDelegate> {
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

@interface PapersViewController : UITableViewController
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

	[centerView release];
	[label release];

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
		else if ([location hasPrefix:kPortoInfantilPortal] || [location hasPrefix:kPortoNivelIPortal] || [location hasPrefix:kPortoNivelIIPortal] || [location hasPrefix:kPortoEMPortal]) {
			$handler([NSHTTPCookie cookiesWithResponseHeaderFields:headerFields forURL:[response URL]], location, nil);
		}
		else {
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
		NSLog(@"gki %@", $gradeKeyItem);

		if (![[$keychainItem objectForKey:(id)kSecAttrAccount] isEqualToString:@""]) {
			$accountInfo = [[NSDictionary dictionaryWithObjectsAndKeys:
				[$keychainItem objectForKey:(id)kSecAttrAccount], kPortoUsernameKey,
				[$keychainItem objectForKey:(id)kSecValueData], kPortoPasswordKey,
				nil] retain];
		}
		else $accountInfo = nil;

		if (![[$gradeKeyItem objectForKey:(id)kSecAttrAccount] isEqualToString:@""]){
			$gradeID = [[$gradeKeyItem objectForKey:(id)kSecValueData] retain];
			NSLog(@"YAY GRADE ID IS COOL %@", $gradeID);
		}
		else $gradeID = nil;
		NSLog(@"i hate you k");

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

	$loadingView = [[LoadingIndicatorView alloc] initWithFrame:[[self view] bounds]];
	[[self view] addSubview:$loadingView];

	$failureView = [[FailView alloc] initWithFrame:[[self view] bounds]];
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
	$contentView = [[UIView alloc] initWithFrame:[[self view] bounds]];
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
			[alert setMessage:[NSString stringWithFormat:@"O portal %@ não é suportado pelo app.", [[error userInfo] objectForKey:@"BadDomain"]]];
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
	NSLog(@"AUTHENTICATE");
	
	NSString *user = [$usernameField text];
	NSString *password = [$passwordField text];
	
	SessionController *controller = [SessionController sharedInstance];
	
	NSDictionary *previousAccountInfo = [controller accountInfo];
	[controller setAccountInfo:[NSDictionary dictionaryWithObjectsAndKeys:
		user, kPortoUsernameKey,
		password, kPortoPasswordKey,
		nil]];
	
	NSLog(@"GONNA LOAD SESSION WITH HANDLER.");
	[controller loadSessionWithHandler:^(BOOL success, NSError *error){
		if (!success) [controller setAccountInfo:previousAccountInfo];
		else [self generateGradeID];

		[self endRequestWithSuccess:success error:error];
	}];
}

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

// [23:41:33] <@DHowett> theiostream: At the top of the function, get 'self.bounds' out into a local variable. each time you call it is a dynamic dispatch because the compiler cannot assume that it has no side-effects
// [23:42:13] <@DHowett> theiostream: the attributed strings and their CTFrameshit should be cached whenver possible. do not create a new attributed string every time the rect is drawn

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
@implementation GradeContainer
@synthesize name, grade, value, average, subGradeContainers, weight, debugLevel, superContainer;

- (id)init {
	if ((self = [super init])) {
		debugLevel = 0;
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
	return [grade floatValue]/[value floatValue]*100;
}

- (BOOL)isAboveAverage {
	return [self $gradePercentage] >= kPortoAverage;
}

- (NSString *)gradePercentage {
	return [NSString stringWithFormat:@"%.2f%%", [self $gradePercentage]];
}

- (void)calculateGradeFromSubgrades {
	NSInteger gradeSum = 0;
	for (GradeContainer *container in [self subGradeContainers])
		gradeSum += [[container grade] floatValue] * [container weight];
	
	[self setGrade:[NSString stringWithFormat:@"%.2f", (double)gradeSum / [self totalWeight]]];
}

- (float)gradeInSupercontainer {
	NSInteger superTotalWeight = [[self superContainer] totalWeight];
	return [[self grade] floatValue] * [self weight] / superTotalWeight;
}

- (void)makeValueTen {
	[self setValue:[@"10,00" americanFloat]];
}

- (void)calculateAverageFromSubgrades {
	NSInteger averageSum = 0;
	for (GradeContainer *container in [self subGradeContainers])
		averageSum += [[container average] floatValue] * [container weight];
	
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
@end

@implementation SubjectTableHeaderView
// Received rect's zone2 is {{rect.size.width, 0}, {rect.size.width/3, rect.size.height}}
- (void)drawDataZoneRect:(CGRect)rect textColor:(CGColorRef)textColor dataFont:(CTFontRef)dataFont boldFont:(CTFontRef)boldFont inContext:(CGContextRef)context {
	CGFloat zoneWidth2 = rect.size.width/4;
	
	CFAttributedStringRef gradeString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Nota\n" stringByAppendingString:[[self container] grade]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange gradeContentRange = CFRangeMake(5, CFAttributedStringGetLength(gradeString_)-5);
	CFAttributedStringRef weightString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Peso\n" stringByAppendingString:[NSString stringWithFormat:@"%d", [[self container] weight]]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange weightContentRange = CFRangeMake(5, CFAttributedStringGetLength(weightString_)-5);
	CFAttributedStringRef averageString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Média\n" stringByAppendingString:[[self container] average]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange averageContentRange = CFRangeMake(5, CFAttributedStringGetLength(averageString_)-5);
	CFAttributedStringRef totalString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Total\n" stringByAppendingString:[NSString stringWithFormat:@"%.2f", [[self container] gradeInSupercontainer]]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
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
	CGFloat zoneWidth2 = rect.size.width / 4;
	
	CFAttributedStringRef gradeString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Nota\n" stringByAppendingString:[[self container] grade]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange gradeContentRange = CFRangeMake(5, CFAttributedStringGetLength(gradeString_)-5);
	CFAttributedStringRef valueString_ = CreateBaseAttributedString(dataFont, textColor, (CFStringRef)[@"Valor\n" stringByAppendingString:[[self container] value]], NO, kCTLineBreakByTruncatingTail, kCTCenterTextAlignment);
	CFRange valueContentRange = CFRangeMake(5, CFAttributedStringGetLength(valueString_)-5);
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
	CTFramesetterRef averageFramesetter = CTFramesetterCreateWithAttributedString(averageString); CFRelease(averageString);
	CTFramesetterRef totalFramesetter = CTFramesetterCreateWithAttributedString(totalString); CFRelease(totalString);
	
	CGRect gradeRect = CGRectMake(rect.origin.x, 0.f, zoneWidth2, rect.size.height);
	CGRect valueRect = CGRectMake(rect.origin.x + zoneWidth2, 0.f, zoneWidth2, rect.size.height);
	CGRect averageRect = CGRectMake(rect.origin.x + zoneWidth2*2, 0.f, zoneWidth2, rect.size.height);
	CGRect totalRect = CGRectMake(rect.origin.x + zoneWidth2*3, 0.f, zoneWidth2, rect.size.height);

	DrawFramesetter(context, gradeFramesetter, gradeRect); CFRelease(gradeFramesetter);
	DrawFramesetter(context, valueFramesetter, valueRect); CFRelease(valueFramesetter);
	DrawFramesetter(context, averageFramesetter, averageRect); CFRelease(averageFramesetter);
	DrawFramesetter(context, totalFramesetter, totalRect); CFRelease(totalFramesetter);
}
@end

@implementation TestView
@synthesize container;

static UIColor *ColorForGrade(NSString *grade_, BOOL graded = YES) {
	UIColor *color;
	
	float grade = [grade_ floatValue];
	if (grade < 6) color = graded ? UIColorFromHexWithAlpha(0xFF3300, 1.f) : UIColorFromHexWithAlpha(0xC75F5F, 1.f);
	else if (grade < 8) color = graded ? UIColorFromHexWithAlpha(0xFFCC00, 1.f) : UIColorFromHexWithAlpha(0xC7A15F, 1.f);
	else color = graded ? UIColorFromHexWithAlpha(0x33CC33, 1.f) : UIColorFromHexWithAlpha(0x5FA4C7, 1.f);
	
	return color;
}

- (void)drawRect:(CGRect)rect {
	NSLog(@"-[TestView drawRect:%@] with %@", NSStringFromCGRect(rect), NSStringFromClass([self class]));
	
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
	CGFloat zoneWidth = rect.size.width/3;
	
	// ZONE 1
	[ColorForGrade([container grade]) setFill];
	CGRect circleRect = CGRectMake(8.f, zoneHeight/2, zoneHeight, zoneHeight);
	CGContextFillEllipseInRect(context, circleRect);
	
	CGColorRef textColor = [[UIColor blackColor] CGColor];

	NSString *systemFont = [[UIFont systemFontOfSize:1.f] fontName];
	CTFontRef dataFont = CTFontCreateWithName((CFStringRef)systemFont, pxtopt(zoneHeight), NULL);
	CTFontRef boldFont = CTFontCreateCopyWithSymbolicTraits(dataFont, pxtopt(zoneHeight), NULL, kCTFontBoldTrait, kCTFontBoldTrait);
	
	CTFramesetterRef fpGradeFramesetter = CreateFramesetter(boldFont, textColor, (CFStringRef)[container grade], NO, kCTLineBreakByTruncatingTail);
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

	[ColorForGrade([container average], NO) setFill];
	CGContextFillRect(context, (CGRect){{baseGraphRect.origin.x, 2.f}, {averageBarWidth, baseGraphRect.size.height}});
	[ColorForGrade([container grade]) setFill];
	CGContextFillRect(context, (CGRect){{baseGraphRect.origin.x, 6.f + baseGraphRect.size.height}, {gradeBarWidth, baseGraphRect.size.height}});
	
	CTFontRef smallerFont = CTFontCreateCopyWithSymbolicTraits(dataFont, pxtopt(baseGraphRect.size.height), NULL, kCTFontBoldTrait, kCTFontBoldTrait);

	CTFramesetterRef gradeBarFramesetter = CreateFramesetter(smallerFont, [[UIColor whiteColor] CGColor], (CFStringRef)[container grade], NO, kCTLineBreakByTruncatingTail);
	CGFloat requiredWidth = CTFramesetterSuggestFrameSizeWithConstraints(gradeBarFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL).width;
	DrawFramesetter(context, gradeBarFramesetter, CGRectMake(baseGraphRect.origin.x + gradeBarWidth - requiredWidth - 3.f, 6.f + baseGraphRect.size.height, requiredWidth, baseGraphRect.size.height)); CFRelease(gradeBarFramesetter);

	CTFramesetterRef averageBarFramesetter = CreateFramesetter(smallerFont, [[UIColor whiteColor] CGColor], (CFStringRef)[container average], NO, kCTLineBreakByTruncatingTail);
	CGFloat requiredWidthAvg = CTFramesetterSuggestFrameSizeWithConstraints(averageBarFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL).width;
	DrawFramesetter(context, averageBarFramesetter, CGRectMake(baseGraphRect.origin.x + averageBarWidth - requiredWidth - 3.f, 2.f, requiredWidthAvg, baseGraphRect.size.height)); CFRelease(averageBarFramesetter);
	
	CFRelease(smallerFont);
	CFRelease(dataFont);
	CFRelease(boldFont);
}

- (void)dealloc {
	[container release];

	[super dealloc];
}
@end

@implementation SubjectGraphView
@synthesize container;

- (void)drawRect:(CGRect)rect {
	CGContextRef context = UIGraphicsGetCurrentContext();
	
	[[UIColor whiteColor] setFill];
	CGContextFillRect(context, rect);
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

		UITableView *tableView = [[UITableView alloc] initWithFrame:(CGRect){{0.f, 0.f}, [self bounds].size} style:UITableViewStylePlain];
		[tableView setDataSource:self];
		[tableView setDelegate:self];
		[tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
		[self addSubview:tableView];
		[tableView release];
		
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

		[tableView setTableHeaderView:tableHeaderView];
		[tableHeaderView release];

		SubjectGraphView *footerView = [[SubjectGraphView alloc] initWithFrame:CGRectMake(0.f, 0.f, [tableView bounds].size.width, 60.f)];
		[footerView setContainer:$container];
		[tableView setTableFooterView:footerView];
		[footerView release];
	}

	return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [[$container subGradeContainers] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
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

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	// FIXME: no more constant 44.f
	UIScrollView *scrollView = [[[UIScrollView alloc] initWithFrame:CGRectMake(0.f, 0.f, tableView.bounds.size.width, 44.f)] autorelease];
	[scrollView setContentSize:CGSizeMake(scrollView.bounds.size.width * 3, scrollView.bounds.size.height)];
	[scrollView setScrollsToTop:NO];
	[scrollView setShowsHorizontalScrollIndicator:NO];
	[scrollView setPagingEnabled:YES];

	SubjectTableHeaderView *headerView = [[SubjectTableHeaderView alloc] initWithFrame:CGRectMake(0.f, 0.f, [scrollView contentSize].width, [scrollView contentSize].height)];
	[headerView setContainer:[[$container subGradeContainers] objectAtIndex:section]];
	[scrollView addSubview:headerView];
	[headerView release];

	return scrollView;
}

- (void)dealloc {
	[$container release];

	[super dealloc];
}
@end

@implementation GradesListViewController
@synthesize year = $year, period = $period;

- (id)init {
	return nil;
}

- (GradesListViewController *)initWithYear:(NSString *)year period:(NSString *)period viewState:(NSString *)viewState eventValidation:(NSString *)eventValidation {
	if ((self = [super init])) {
		$viewState = [viewState retain];
		$eventValidation = [eventValidation retain];

		[self setYear:year];
		[self setPeriod:period];

		$rootContainer = nil;
	}

	return self;
}

- (void)reloadData {
	[super reloadData];
	SessionController *sessionController = [SessionController sharedInstance];
	
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

	XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
	XMLElement *divGeral = [document firstElementMatchingPath:@"/html/body/form[@id='form1']/div[@class='page ui-corner-bottom']/div[@class='body']/div[@id='updtPnl1']/div[@id='ContentPlaceHolder1_divGeral']"];
	NSLog(@"divGeral: %@", divGeral);
	
	NSString *information = [[divGeral firstElementMatchingPath:@"./div[@id='ContentPlaceHolder1_divTurma']/h3"] content];
	NSLog(@"information: %@", information);

	XMLElement *table = [divGeral firstElementMatchingPath:@"./table[@id='ContentPlaceHolder1_dlMaterias']"];
	NSLog(@"table: %@", table);
	NSArray *subjectElements = [table elementsMatchingPath:@"./tr/td/div[@class='container']"];
	NSLog(@"subjectElements: %@", subjectElements);
	
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
		
		NSString *subjectName = [[container firstElementMatchingPath:@"./h2[@class='fleft m10r ']/span"] content];
		subjectName = [subjectName stringByReplacingOccurrencesOfString:@"LÍNG. ESTR. MOD. " withString:@""]; // remove LING ESTR MOD. I can now live in peace.
		// B-Zug Fächer handeln
		// denn ich kann
		if ([subjectName hasPrefix:@"*"]) {
			subjectName = [[subjectName substringFromIndex:1] substringToIndex:[subjectName length]-2];
			subjectName = [subjectName stringByAppendingString:@" \ue50e"]; // \ue50e is meant to be a DE flag.
		}
		else if ([subjectName isEqualToString:@"ARTES VISUAIS"]) continue; // Fix a (porto) bug where we get DE + non-DE Kunst.

		[subjectContainer setName:subjectName];

		NSString *totalGrade = [[[[container firstElementMatchingPath:@"./h2[@class='fright ']/span/span[1]/span"] content] componentsSeparatedByString:@":"] objectAtIndex:1];
		[subjectContainer setGrade:[totalGrade americanFloat]];
		NSString *averageGrade = [[[[container firstElementMatchingPath:@"./h2[@class='fright ']/span/span[2]/span"] content] componentsSeparatedByString:@": "] objectAtIndex:1];
		[subjectContainer setAverage:[averageGrade americanFloat]];
		
		// TODO: Optimize this into a recursive routine.
		NSArray *subjectGrades = [[container firstElementMatchingPath:@"./div/table[starts-with(@id, 'ContentPlaceHolder1_dlMaterias_gvNotas')]"] elementsMatchingPath:@"./tr[@class!='headerTable1 p3']"];
		NSMutableArray *subGradeContainers = [NSMutableArray array];
		for (XMLElement *subsection in subjectGrades) {
			GradeContainer *subGradeContainer = [[[GradeContainer alloc] init] autorelease];
			[subGradeContainer setSuperContainer:subjectContainer];
			[subGradeContainer setDebugLevel:2];
			[subGradeContainer makeValueTen];

			NSString *subsectionName = [[subsection firstElementMatchingPath:@"./td[2]"] content];
			NSArray *split = [subsectionName componentsSeparatedByString:@" - "];
			[subGradeContainer setName:[split objectAtIndex:1]];
			[subGradeContainer setWeight:[[[split objectAtIndex:0] substringWithRange:NSMakeRange(3, 1)] integerValue]];

			NSString *subsectionGrade = [[subsection firstElementMatchingPath:@"./td[3]"] content];
			[subGradeContainer setGrade:[subsectionGrade americanFloat]];
			NSString *subsectionAverage = [[subsection firstElementMatchingPath:@"./td[4]"] content];
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

					NSString *subsubsectionName = [[[subsubsection firstElementMatchingPath:@"./td[1]"] content] substringFromIndex:5];
					[subsubsectionGradeContainer setName:subsubsectionName];
					NSString *subsubsectionGrade = [[subsubsection firstElementMatchingPath:@"./td[2]"] content];
					[subsubsectionGradeContainer setGrade:[subsubsectionGrade americanFloat]];
					NSString *subsubsectionValue = [[subsubsection firstElementMatchingPath:@"./td[3]"] content];
					[subsubsectionGradeContainer setValue:[subsubsectionValue americanFloat]];
					NSString *subsubsectionAverage = [[subsubsection firstElementMatchingPath:@"./td[4]"] content];
					[subsubsectionGradeContainer setAverage:[subsubsectionAverage americanFloat]];

					[subsubGradeContainers addObject:subsubsectionGradeContainer];
				}
			}
			
			[subGradeContainer setSubGradeContainers:subsubGradeContainers];
			[subGradeContainers addObject:subGradeContainer];
		}
		
		[subjectContainer setSubGradeContainers:subGradeContainers];
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
		NSLog(@"content view is %@ so wat.", $contentView);
	}];
}

- (void)loadContentView {
	UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0.f, 0.f, [self view].bounds.size.width, [self view].bounds.size.height)];
	[scrollView setBackgroundColor:[UIColor whiteColor]];
	[scrollView setScrollsToTop:NO];
	[scrollView setPagingEnabled:YES];

	$contentView = scrollView;
}

- (void)prepareContentView {
	UIScrollView *contentView = (UIScrollView *)$contentView;
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
	UITableView *tableView = [[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStylePlain];
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
- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor blueColor]];
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

	PapersViewController *papersViewController = [[[PapersViewController alloc] init] autorelease];
	[papersViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Circulares" image:nil tag:0] autorelease]];

	ServicesViewController *servicesViewController = [[[ServicesViewController alloc] init] autorelease];
	[servicesViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Serviços" image:nil tag:0] autorelease]];

	AccountViewController *accountViewController = [[[AccountViewController alloc] init] autorelease];
	UINavigationController *accountNavViewController = [[[UINavigationController alloc] initWithRootViewController:accountViewController] autorelease];
	[accountNavViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Conta" image:nil tag:0] autorelease]];

	NSArray *controllers = [NSArray arrayWithObjects:
		newsNavController,
		gradesNavController,
		papersViewController,
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

