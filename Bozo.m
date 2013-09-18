/* PortoApp
 iOS interface to the Colégio Visconde de Porto Seguro grade/news etc.
 
 Created by Daniel Ferreira in 9/09/2013
 
 Licensed under the GNU General Public License version 3.
 */

/* Credits {{{

Personal thanks:
- Guilherme Stark
- Max Shavrick
 
Project Thanks:
- HNKit (session design inspiration)
- MobileCydia.mm (goes without saying)

Code taken from third parties:
- XML classes were reproduced from Grant Paul (chpwn)'s HNKit.
(c) 2013 Xuzz Productions LLC

- LoginController, LoadingIndicatorView were changed minorly from Grant Paul (chpwn)'s news:yc.
(c) 2011 Xuzz Productions LLC

- KeychainItemWrapper was reproduced from Apple's GenericKeychain sample project.
(c) 2010 Apple Inc.

}}} */

/* Include {{{ */
#import <UIKit/UIKit.h>
#import <Security/Security.h>
/* }}} */

/* External {{{ */

/* URL Encoding {{{ */
static NSString *NSStringURLEncode(NSString *string) {
	return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)string, NULL, CFSTR("!*'();:@&;=+$,/%?#[]"), kCFStringEncodingUTF8) autorelease];
}
/* }}} */

/* Keychain {{{ */
@interface KeychainItemWrapper : NSObject {
    NSMutableDictionary *keychainItemData;      // The actual keychain item data backing store.
    NSMutableDictionary *genericPasswordQuery;  // A placeholder for the generic keychain item query used to locate the item.
}
 
@property (nonatomic, retain) NSMutableDictionary *keychainItemData;
@property (nonatomic, retain) NSMutableDictionary *genericPasswordQuery;
 
// Designated initializer.
- (id)initWithIdentifier: (NSString *)identifier accessGroup:(NSString *) accessGroup;
- (void)setObject:(id)inObject forKey:(id)key;
- (id)objectForKey:(id)key;
 
// Initializes and resets the default generic keychain item data.
- (void)resetKeychainItem;
 
@end

@interface KeychainItemWrapper (PrivateMethods)
/*
The decision behind the following two methods (secItemFormatToDictionary and dictionaryToSecItemFormat) was
to encapsulate the transition between what the detail view controller was expecting (NSString *) and what the
Keychain API expects as a validly constructed container class.
*/
- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert;
- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert;
 
// Updates the item in the keychain, or adds it if it doesn't exist.
- (void)writeToKeychain;
 
@end
 
@implementation KeychainItemWrapper
 
@synthesize keychainItemData, genericPasswordQuery;
 
- (id)initWithIdentifier: (NSString *)identifier accessGroup:(NSString *) accessGroup;
{
    if (self = [super init])
    {
        // Begin Keychain search setup. The genericPasswordQuery leverages the special user
        // defined attribute kSecAttrGeneric to distinguish itself between other generic Keychain
        // items which may be included by the same application.
        genericPasswordQuery = [[NSMutableDictionary alloc] init];
        
        [genericPasswordQuery setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
        [genericPasswordQuery setObject:identifier forKey:(id)kSecAttrGeneric];
        
        // The keychain access group attribute determines if this item can be shared
        // amongst multiple apps whose code signing entitlements contain the same keychain access group.
        if (accessGroup != nil)
        {
#if TARGET_IPHONE_SIMULATOR
            // Ignore the access group if running on the iPhone simulator.
            // 
            // Apps that are built for the simulator aren't signed, so there's no keychain access group
            // for the simulator to check. This means that all apps can see all keychain items when run
            // on the simulator.
            //
            // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
            // simulator will return -25243 (errSecNoAccessForItem).
#else           
            [genericPasswordQuery setObject:accessGroup forKey:(id)kSecAttrAccessGroup];
#endif
        }
        
        // Use the proper search constants, return only the attributes of the first match.
        [genericPasswordQuery setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
        [genericPasswordQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
        
        NSDictionary *tempQuery = [NSDictionary dictionaryWithDictionary:genericPasswordQuery];
        
        NSMutableDictionary *outDictionary = nil;
        
        if (! SecItemCopyMatching((CFDictionaryRef)tempQuery, (CFTypeRef *)&outDictionary) == noErr)
        {
            // Stick these default values into keychain item if nothing found.
            [self resetKeychainItem];
            
            // Add the generic attribute and the keychain access group.
            [keychainItemData setObject:identifier forKey:(id)kSecAttrGeneric];
            if (accessGroup != nil)
            {
#if TARGET_IPHONE_SIMULATOR
                // Ignore the access group if running on the iPhone simulator.
                // 
                // Apps that are built for the simulator aren't signed, so there's no keychain access group
                // for the simulator to check. This means that all apps can see all keychain items when run
                // on the simulator.
                //
                // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
                // simulator will return -25243 (errSecNoAccessForItem).
#else           
                [keychainItemData setObject:accessGroup forKey:(id)kSecAttrAccessGroup];
#endif
            }
        }
        else
        {
            // load the saved data from Keychain.
            self.keychainItemData = [self secItemFormatToDictionary:outDictionary];
        }
       
        [outDictionary release];
    }
    
    return self;
}
 
- (void)dealloc
{
    [keychainItemData release];
    [genericPasswordQuery release];
    
    [super dealloc];
}
 
- (void)setObject:(id)inObject forKey:(id)key 
{
    if (inObject == nil) return;
    id currentObject = [keychainItemData objectForKey:key];
    if (![currentObject isEqual:inObject])
    {
        [keychainItemData setObject:inObject forKey:key];
        [self writeToKeychain];
    }
}
 
- (id)objectForKey:(id)key
{
    return [keychainItemData objectForKey:key];
}
 
- (void)resetKeychainItem
{
    OSStatus junk = noErr;
    if (!keychainItemData) 
    {
        self.keychainItemData = [[NSMutableDictionary alloc] init];
    }
    else if (keychainItemData)
    {
        NSMutableDictionary *tempDictionary = [self dictionaryToSecItemFormat:keychainItemData];
        junk = SecItemDelete((CFDictionaryRef)tempDictionary);
        NSAssert( junk == noErr || junk == errSecItemNotFound, @"Problem deleting current dictionary." );
    }
    
    // Default attributes for keychain item.
    [keychainItemData setObject:@"" forKey:(id)kSecAttrAccount];
    [keychainItemData setObject:@"" forKey:(id)kSecAttrLabel];
    [keychainItemData setObject:@"" forKey:(id)kSecAttrDescription];
    
    // Default data for keychain item.
    [keychainItemData setObject:@"" forKey:(id)kSecValueData];
}
 
- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for a SecItem.
    
    // Create a dictionary to return populated with the attributes and data.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the Generic Password keychain item class attribute.
    [returnDictionary setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    
    // Convert the NSString to NSData to meet the requirements for the value type kSecValueData.
    // This is where to store sensitive data that should be encrypted.
    NSString *passwordString = [dictionaryToConvert objectForKey:(id)kSecValueData];
    [returnDictionary setObject:[passwordString dataUsingEncoding:NSUTF8StringEncoding] forKey:(id)kSecValueData];
    
    return returnDictionary;
}
 
- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert
{
    // The assumption is that this method will be called with a properly populated dictionary
    // containing all the right key/value pairs for the UI element.
    
    // Create a dictionary to return populated with the attributes and data.
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionaryToConvert];
    
    // Add the proper search key and class attribute.
    [returnDictionary setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    [returnDictionary setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    
    // Acquire the password data from the attributes.
    NSData *passwordData = NULL;
    if (SecItemCopyMatching((CFDictionaryRef)returnDictionary, (CFTypeRef *)&passwordData) == noErr)
    {
        // Remove the search, class, and identifier key/value, we don't need them anymore.
        [returnDictionary removeObjectForKey:(id)kSecReturnData];
        
        // Add the password to the dictionary, converting from NSData to NSString.
        NSString *password = [[[NSString alloc] initWithBytes:[passwordData bytes] length:[passwordData length] 
                                                     encoding:NSUTF8StringEncoding] autorelease];
        [returnDictionary setObject:password forKey:(id)kSecValueData];
    }
    else
    {
        // Don't do anything if nothing is found.
        NSAssert(NO, @"Serious error, no matching item found in the keychain.\n");
    }
    
    [passwordData release];
   
    return returnDictionary;
}
 
- (void)writeToKeychain
{
    NSDictionary *attributes = NULL;
    NSMutableDictionary *updateItem = NULL;
    OSStatus result;
    
    if (SecItemCopyMatching((CFDictionaryRef)genericPasswordQuery, (CFTypeRef *)&attributes) == noErr)
    {
        // First we need the attributes from the Keychain.
        updateItem = [NSMutableDictionary dictionaryWithDictionary:attributes];
        // Second we need to add the appropriate search key/values.
        [updateItem setObject:[genericPasswordQuery objectForKey:(id)kSecClass] forKey:(id)kSecClass];
        
        // Lastly, we need to set up the updated attribute list being careful to remove the class.
        NSMutableDictionary *tempCheck = [self dictionaryToSecItemFormat:keychainItemData];
        [tempCheck removeObjectForKey:(id)kSecClass];
        
#if TARGET_IPHONE_SIMULATOR
        // Remove the access group if running on the iPhone simulator.
        // 
        // Apps that are built for the simulator aren't signed, so there's no keychain access group
        // for the simulator to check. This means that all apps can see all keychain items when run
        // on the simulator.
        //
        // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
        // simulator will return -25243 (errSecNoAccessForItem).
        //
        // The access group attribute will be included in items returned by SecItemCopyMatching,
        // which is why we need to remove it before updating the item.
        [tempCheck removeObjectForKey:(id)kSecAttrAccessGroup];
#endif
        
        // An implicit assumption is that you can only update a single item at a time.
        
        result = SecItemUpdate((CFDictionaryRef)updateItem, (CFDictionaryRef)tempCheck);
        NSAssert( result == noErr, @"Couldn't update the Keychain Item." );
    }
    else
    {
        // No previous item found; add the new one.
        result = SecItemAdd((CFDictionaryRef)[self dictionaryToSecItemFormat:keychainItemData], NULL);
        NSAssert( result == noErr, @"Couldn't add the Keychain Item." );
    }
}
 
@end

/* }}} */

/* XML {{{ */

#import <libxml/tree.h>
#import <libxml/parser.h>
#import <libxml/HTMLparser.h>
#import <libxml/xpath.h>
#import <libxml/xpathInternals.h>

@class XMLDocument;
@interface XMLElement : NSObject {
    xmlNodePtr node;
    XMLDocument *document;
    
    NSArray *cachedChildren;
    NSDictionary *cachedAttributes;
    NSString *cachedContent;
}

- (id)initWithNode:(xmlNodePtr)node_ inDocument:(XMLDocument *)document_;
- (NSString *)content;
- (NSString *)tagName;
- (NSArray *)children;
- (NSDictionary *)attributes;
- (NSString *)attributeWithName:(NSString *)name;
- (BOOL)isTextNode;
- (xmlNodePtr)node;

- (NSArray *)elementsMatchingPath:(NSString *)xpath;
- (XMLElement *)firstElementMatchingPath:(NSString *)xpath;
@end


@interface XMLDocument : NSObject {
    xmlDocPtr document;
}

- (id)initWithHTMLData:(NSData *)data_;
- (id)initWithXMLData:(NSData *)data_;
- (NSArray *)elementsMatchingPath:(NSString *)query relativeToElement:(XMLElement *)element;
- (NSArray *)elementsMatchingPath:(NSString *)xpath;
- (XMLElement *)firstElementMatchingPath:(NSString *)xpath;
- (xmlDocPtr)document;
@end

static int XMLElementOutputWriteCallback(void *context, const char *buffer, int len) {
    NSMutableData *data = context;
    [data appendBytes:buffer length:len];
    return len;
}

static int XMLElementOutputCloseCallback(void *context) {
    NSMutableData *data = context;
    [data release];
    return 0;
}

@implementation XMLElement
- (void)dealloc {
    [cachedChildren release];
    [cachedAttributes release];
    [cachedContent release];
    [document release];
    
    [super dealloc];
}

- (id)initWithNode:(xmlNodePtr)node_ inDocument:(XMLDocument *)document_ {
    if ((self = [super init])) {
        node = node_;
        document = [document_ retain];
    }

    return self;
}

- (NSUInteger)hash {
    return (NSUInteger) node;
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[XMLElement class]]) {
        XMLElement *other = (XMLElement *)object;
        return [other node] == node;
    } else {
        return NO;
    }
}

- (NSString *)content {
    if (cachedContent != nil) return cachedContent;
    
    NSMutableString *content = [[NSMutableString string] retain];
    
    if (![self isTextNode]) {
        xmlNodePtr children = node->children;
    
        while (children) {
            NSMutableData *data = [[NSMutableData alloc] init];
            xmlOutputBufferPtr buffer = xmlOutputBufferCreateIO(XMLElementOutputWriteCallback, XMLElementOutputCloseCallback, data, NULL);
            xmlNodeDumpOutput(buffer, [document document], children, 0, 0, "utf-8");
            xmlOutputBufferFlush(buffer);
            [content appendString:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
            xmlOutputBufferClose(buffer);
            
            children = children->next;
        }
    } else {
        xmlChar *nodeContent = xmlNodeGetContent(node);
        [content appendString:[NSString stringWithUTF8String:(char *) nodeContent]];
        xmlFree(nodeContent);
    }
    
    cachedContent = content;
    return cachedContent;
}


- (NSString *)tagName {
    if ([self isTextNode]) return nil;
    
    char *nodeName = (char *) node->name;
    if (nodeName == NULL) nodeName = "";
    
    NSString *name = [NSString stringWithUTF8String:nodeName];
    return name;
}

- (NSArray *)children {
    if (cachedChildren != nil) return cachedChildren;
    
    xmlNodePtr list = node->children;
    NSMutableArray *children = [NSMutableArray array];
        
    while (list) {
        XMLElement *element = [[XMLElement alloc] initWithNode:list inDocument:document];
        [children addObject:[element autorelease]];
        
        list = list->next;
    }
    
    cachedChildren = [children retain];
    return cachedChildren;
}

- (NSDictionary *)attributes {
    if (cachedAttributes != nil) return cachedAttributes;
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    xmlAttrPtr list = node->properties;
    
    while (list) {
        NSString *name = nil, *value = nil;
        
        name = [NSString stringWithCString:(const char *) list->name encoding:NSUTF8StringEncoding];
        if (list->children != NULL && list->children->content != NULL) {
            value = [NSString stringWithCString:(const char *) list->children->content encoding:NSUTF8StringEncoding];
        }
        
        if (name != nil && value != nil) {
            [attributes setObject:value forKey:name];
        }
                    
        list = list->next;
    }

    cachedAttributes = [attributes retain];
    return cachedAttributes;
}

- (NSString *)attributeWithName:(NSString *)name {
    return [[self attributes] objectForKey:name];
}

- (BOOL)isTextNode {
    return node->type == XML_TEXT_NODE;
}

- (xmlNodePtr)node {
    return node;
}

- (NSArray *)elementsMatchingPath:(NSString *)xpath {
    return [document elementsMatchingPath:xpath relativeToElement:self];
}

- (XMLElement *)firstElementMatchingPath:(NSString *)xpath {
    NSArray *elements = [self elementsMatchingPath:xpath];

    if ([elements count] >= 1) {
        return [elements objectAtIndex:0];
    } else {
        return nil;
    }
}
@end

@implementation XMLDocument

- (void)dealloc {
    xmlFreeDoc(document);
    [super dealloc];
}

- (id)initWithData:(NSData *)data isXML:(BOOL)xml {
    if ((self = [super init])) {
        document = (xml ? xmlReadMemory : htmlReadMemory)([data bytes], [data length], "", NULL, xml ? XML_PARSE_RECOVER : HTML_PARSE_NOWARNING | HTML_PARSE_NOERROR);
        
        if (document == NULL) {
            [self autorelease];
            return nil;
        }
    }

    return self;
}

- (xmlDocPtr)document {
    return document;
}

- (id)initWithXMLData:(NSData *)data_ {
    return [self initWithData:data_ isXML:YES];
}

- (id)initWithHTMLData:(NSData *)data_ {
  return [self initWithData:data_ isXML:NO];
}

- (NSArray *)elementsMatchingPath:(NSString *)query relativeToElement:(XMLElement *)element {
    xmlXPathContextPtr xpathCtx;
    xmlXPathObjectPtr xpathObj;
    
    xpathCtx = xmlXPathNewContext(document);
    if (xpathCtx == NULL) return nil;

    xpathCtx->node = [element node];
    
    xpathObj = xmlXPathEvalExpression((xmlChar *) [query cStringUsingEncoding:NSUTF8StringEncoding], xpathCtx);
    if (xpathObj == NULL) return nil;
    
    xmlNodeSetPtr nodes = xpathObj->nodesetval;
    if (nodes == NULL) return nil;
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSInteger i = 0; i < nodes->nodeNr; i++) {
        XMLElement *element = [[XMLElement alloc] initWithNode:nodes->nodeTab[i] inDocument:self];
        [result addObject:[element autorelease]];
    }
    
    xmlXPathFreeObject(xpathObj);
    xmlXPathFreeContext(xpathCtx);
    
    return result;
}

- (NSArray *)elementsMatchingPath:(NSString *)xpath {
    return [self elementsMatchingPath:xpath relativeToElement:nil];
}

- (XMLElement *)firstElementMatchingPath:(NSString *)xpath {
    NSArray *elements = [self elementsMatchingPath:xpath];
    
    if ([elements count] >= 1) {
        return [elements objectAtIndex:0];
    } else {
        return nil;
    }
}

@end

/* }}} */

/* }}} */

/* Constants {{{ */

#define kPortoRootURL @"http://www.portoseguro.org.br/"

/* }}} */

/* Macros {{{ */

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

	NSDictionary *$accountInfo;
	NSDictionary *$sessionInfo;
}
+ (SessionController *)sharedInstance;

- (NSDictionary *)accountInfo;
- (void)setAccountInfo:(NSDictionary *)secInfo;
- (BOOL)hasAccount;

- (NSDictionary *)sessionInfo;
- (void)setSessionInfo:(NSDictionary *)sessionInfo;

- (void)loadSessionWithHandler:(void(^)(BOOL, NSError *))handler;

/* do stuff like "API Call to Something" from here */
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

/* }}} */

/* Controllers {{{ */

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

@interface NewsViewController : UITableViewController {
	UITableView *$tableView;
	UITableViewCell *$loadingCell;
	
	NSMutableArray *$imageData;
	BOOL $isLoading;
}
@end

/* }}} */

/* Grades {{{ */

@interface GradesViewController : UIViewController
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

@interface AccountViewController : UIViewController
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
        
        CGSize viewsize = frame.size;
        CGSize spinnersize = [spinner_ bounds].size;
        CGSize textsize = [[label_ text] sizeWithFont:[label_ font]];
        float bothwidth = spinnersize.width + textsize.width + 5.0f;
        
        CGRect containrect = {
            CGPointMake(floorf((viewsize.width / 2) - (bothwidth / 2)), floorf((viewsize.height / 2) - (spinnersize.height / 2))),
            CGSizeMake(bothwidth, spinnersize.height)
        };
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
        [self addSubview:container_];
    } return self;
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
#define kPortoASPSessionCookie @"ASPSESSIONID"

#define kPortoUsernameKey @"PortoUsernameKey"
#define kPortoPasswordKey @"PortoPasswordKey"

#define kPortoPortalKey @"PortoPortalKey"
#define kPortoCookieKey @"PortoCookieKey"
#define kPortoNameKey @"PortoNameKey"
#define kPortoGradeKey @"PortoGradeKey"
#define kPortoGenderKey @"PortoGenderKey"

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
		if (![[$keychainItem objectForKey:(id)kSecAttrAccount] isEqualToString:@""]) {
			$accountInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
				[$keychainItem objectForKey:(id)kSecAttrAccount], kPortoUsernameKey,
				[$keychainItem objectForKey:(id)kSecValueData], kPortoPasswordKey,
				nil];
		}
		else $accountInfo = nil;

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

- (NSDictionary *)sessionInfo {
	return $sessionInfo;
}

- (void)setSessionInfo:(NSDictionary *)sessionInfo {
	if ($sessionInfo != nil) [$sessionInfo release];
	$sessionInfo = [sessionInfo retain];
}

- (void)loadSessionWithHandler:(void(^)(BOOL, NSError *))handler {
	SessionAuthenticator *authenticator = [[SessionAuthenticator alloc] initWithUsername:[$accountInfo objectForKey:kPortoUsernameKey] password:[$accountInfo objectForKey:kPortoPasswordKey]];
	[authenticator authenticateWithHandler:^(NSArray *cookies, NSString *portal, NSError *error){
		NSLog(@"Cookies: %@", cookies);
		
		if (portal != nil) {
			NSString *sessionCookie;
			NSString *nameCookie;
			NSString *gradeCookie;
			NSString *genderCookie;

			for (NSHTTPCookie *cookie in cookies) {
				NSString *name = [cookie name];
				if ([name isEqualToString:kPortoGenderCookie]) genderCookie = [cookie value];
				else if ([name isEqualToString:kPortoGradeCookie]) gradeCookie = [cookie value];
				else if ([name isEqualToString:kPortoNameCookie]) nameCookie = [cookie value];
				else if ([name hasPrefix:kPortoASPSessionCookie]) sessionCookie = [cookie value];
			}
			
			NSDictionary *sessionInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				portal, kPortoPortalKey,
				sessionCookie, kPortoCookieKey,
				nameCookie, kPortoNameKey,
				gradeCookie, kPortoGradeKey,
				genderCookie, kPortoGenderKey,
				nil];
			[self setSessionInfo:sessionInfo];

			handler(YES, nil);
		}
		else handler(NO, error);
	}];
	[authenticator release];
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
    
    UIViewAnimationCurve curve = [[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
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

	[$bottomLabel setText:@"Seus dados são apenas mandados ao Porto."];
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

	[controller setAccountInfo:[NSDictionary dictionaryWithObjectsAndKeys:
		user, kPortoUsernameKey,
		password, kPortoPasswordKey,
		nil]];
	
	[controller loadSessionWithHandler:^(BOOL success, NSError *error){
		if (!success) [controller setAccountInfo:nil];
		[self endRequestWithSuccess:success error:error];
	}];
}
@end
/* }}} */

/* }}} */

/* News Controller {{{ */

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
	[$tableView setScrollEnabled:NO];
	[self setTableView:$tableView];

	$loadingCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	LoadingIndicatorView *loadingIndicatorView = [[[LoadingIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 200, 50)] autorelease];
	[loadingIndicatorView setCenter:[$loadingCell center]];
	[$loadingCell addSubview:loadingIndicatorView];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://www.portoseguro.org.br"]];
		
		XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
		NSArray *list = [document elementsMatchingPath:@"//body/div[@id = 'main']/div[@id = 'banner']/div[@id = 'bannerFoto']/ul/li"];
		
		for (XMLElement *banner in list) {
			XMLElement *span = [banner firstElementMatchingPath:@".//div/span"];
			XMLElement *a = [banner firstElementMatchingPath:@".//a"];
			
			XMLElement *img = [banner firstElementMatchingPath:@".//a/img"];
			UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:[kPortoRootURL stringByAppendingString:[[img attributes] objectForKey:@"src"]]]]];
			
			NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
				[span content], @"Porto",
				[[a attributes] objectForKey:@"href"], @"Link",
				image, @"Image",
				nil];
			[$imageData addObject:result];
		}

		NSLog(@"ARRY %@", $imageData);
		
		$isLoading = NO;

		[$tableView setScrollEnabled:YES];
		[$tableView reloadData];
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
	return $isLoading ? [[self tableView] bounds].size.height : 70.f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ($isLoading) return $loadingCell;
	
	static NSString *cellIdentifier = @"PortoNewsCellIdentifier";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier] autorelease];
		
		UIImageView *imageView = [[[UIImageView alloc] initWithFrame:CGRectMake(0.f, 0.f, [tableView bounds].size.width, 70.f)] autorelease];
		[imageView setImage:[[$imageData objectAtIndex:[indexPath section]] objectForKey:@"Image"]];
		[[cell contentView] addSubview:imageView];
	}

	return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if ($isLoading) return nil;
	
	NSString *text = [[$imageData objectAtIndex:section] objectForKey:@"Porto"];
	if ([text isEqualToString:@""]) text = @"Institucional";

	UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, [tableView bounds].size.width, 30.f)] autorelease];
	[view setBackgroundColor:[UIColor redColor]];
	
	UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(10.f, 3.f, [tableView bounds].size.width - 12.f, 24.f)] autorelease];
	[label setBackgroundColor:[UIColor clearColor]];
	[label setTextColor:[UIColor whiteColor]];
	[label setFont:[UIFont systemFontOfSize:19.f]];
	[label setText:text];
	[view addSubview:label];

	return view;
}

- (void)dealloc {
	[$tableView release];
	[$loadingCell release];
	[$imageData release];

	[super dealloc];
}
@end

/* }}} */

/* Grades Controller {{{ */

@implementation GradesViewController
- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor blueColor]];
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
@end

/* }}} */

/* App Delegate {{{ */

@implementation AppDelegate
@synthesize window = $window;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
	$window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	
	NewsViewController *newsViewController = [[[NewsViewController alloc] init] autorelease];
	[newsViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notícias" image:nil tag:0] autorelease]];

	GradesViewController *gradesViewController = [[[GradesViewController alloc] init] autorelease];
	[gradesViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notas" image:nil tag:0] autorelease]];

	PapersViewController *papersViewController = [[[PapersViewController alloc] init] autorelease];
	[papersViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Circulares" image:nil tag:0] autorelease]];

	ServicesViewController *servicesViewController = [[[ServicesViewController alloc] init] autorelease];
	[servicesViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Serviços" image:nil tag:0] autorelease]];

	AccountViewController *accountViewController = [[[AccountViewController alloc] init] autorelease];
	[accountViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Conta" image:nil tag:0] autorelease]];

	NSArray *controllers = [NSArray arrayWithObjects:
		newsViewController,
		gradesViewController,
		papersViewController,
		servicesViewController,
		accountViewController,
		nil];
	$tabBarController = [[UITabBarController alloc] init];
	[$tabBarController setViewControllers:controllers];
    
	[$window setRootViewController:$tabBarController];
	[$window makeKeyAndVisible];
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
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int ret = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    
	[pool drain];
	return ret;
}

/* }}} */

/* }}} */
