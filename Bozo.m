/* PortoApp
 iOS interface to the Colégio Visconde de Porto Seguro grade/news etc.
 
 Created by Daniel Ferreira in 9/09/2013
 
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
/* }}} */

/* External {{{ */

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

/* ABTableViewCell {{{ */

@interface ABTableViewCell : UITableViewCell {
	UIView* contentView;
	UIView* selectedContentView;
}

- (void)drawContentView:(CGRect)rect highlighted:(BOOL)highlighted; // subclasses should implement
@end

@interface ABTableViewCellView : UIView
@end

@interface ABTableViewSelectedCellView : UIView
@end

@implementation ABTableViewCellView
- (id)initWithFrame:(CGRect)frame {
	if((self = [super initWithFrame:frame])) {
		self.contentMode = UIViewContentModeRedraw;
	}

	return self;
}

- (void)drawRect:(CGRect)rect {
	[(ABTableViewCell *)[self superview] drawContentView:rect highlighted:NO];
}
@end

@implementation ABTableViewSelectedCellView
- (id)initWithFrame:(CGRect)frame {
	if((self = [super initWithFrame:frame])) {
		self.contentMode = UIViewContentModeRedraw;
	}

	return self;
}

- (void)drawRect:(CGRect)rect {
	[(ABTableViewCell *)[self superview] drawContentView:rect highlighted:YES];
}
@end


@implementation ABTableViewCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if(self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
		contentView = [[ABTableViewCellView alloc] initWithFrame:CGRectZero];
		contentView.opaque = YES;
		self.backgroundView = contentView;
		[contentView release];

		selectedContentView = [[ABTableViewSelectedCellView alloc] initWithFrame:CGRectZero];
		selectedContentView.opaque = YES;
		self.selectedBackgroundView = selectedContentView;
		[selectedContentView release];

    }

    return self;
}

- (void)dealloc {
	[super dealloc];
}

- (void)setSelected:(BOOL)selected {
	[selectedContentView setNeedsDisplay];

	if(!selected && self.selected) {
		[contentView setNeedsDisplay];
	}

	[super setSelected:selected];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
	[selectedContentView setNeedsDisplay];

	if(!selected && self.selected) {
		[contentView setNeedsDisplay];
	}

	[super setSelected:selected animated:animated];
}

- (void)setHighlighted:(BOOL)highlighted {
	[selectedContentView setNeedsDisplay];

	if(!highlighted && self.highlighted) {
		[contentView setNeedsDisplay];
	}

	[super setHighlighted:highlighted];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
	[selectedContentView setNeedsDisplay];

	if(!highlighted && self.highlighted) {
		[contentView setNeedsDisplay];
	}

	[super setHighlighted:highlighted animated:animated];
}

- (void)setFrame:(CGRect)f {
	[super setFrame:f];
	CGRect b = [self bounds];
	// b.size.height -= 1; // leave room for the seperator line
	[contentView setFrame:b];
	[selectedContentView setFrame:b];
}

- (void)setNeedsDisplay {
	[super setNeedsDisplay];
	[contentView setNeedsDisplay];

	if([self isHighlighted] || [self isSelected]) {
		[selectedContentView setNeedsDisplay];
	}
}

- (void)setNeedsDisplayInRect:(CGRect)rect {
	[super setNeedsDisplayInRect:rect];
	[contentView setNeedsDisplayInRect:rect];

	if([self isHighlighted] || [self isSelected]) {
		[selectedContentView setNeedsDisplayInRect:rect];
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	self.contentView.hidden = YES;
	[self.contentView removeFromSuperview];
}

- (void)drawContentView:(CGRect)rect highlighted:(BOOL)highlighted {
	return;
}
@end

/* }}} */

/* HTML NSString {{{ */

@interface NSString (GTMNSStringHTMLAdditions)
- (NSString *)gtm_stringByEscapingForHTML;
- (NSString *)gtm_stringByEscapingForAsciiHTML;
- (NSString *)gtm_stringByUnescapingFromHTML;
@end

typedef struct {
  NSString *escapeSequence;
  unichar uchar;
} HTMLEscapeMap;

// Taken from http://www.w3.org/TR/xhtml1/dtds.html#a_dtd_Special_characters
// Ordered by uchar lowest to highest for bsearching
static HTMLEscapeMap gAsciiHTMLEscapeMap[] = {
  // A.2.2. Special characters
  { @"&quot;", 34 },
  { @"&amp;", 38 },
  { @"&apos;", 39 },
  { @"&lt;", 60 },
  { @"&gt;", 62 },
  
    // A.2.1. Latin-1 characters
  { @"&nbsp;", 160 }, 
  { @"&iexcl;", 161 }, 
  { @"&cent;", 162 }, 
  { @"&pound;", 163 }, 
  { @"&curren;", 164 }, 
  { @"&yen;", 165 }, 
  { @"&brvbar;", 166 }, 
  { @"&sect;", 167 }, 
  { @"&uml;", 168 }, 
  { @"&copy;", 169 }, 
  { @"&ordf;", 170 }, 
  { @"&laquo;", 171 }, 
  { @"&not;", 172 }, 
  { @"&shy;", 173 }, 
  { @"&reg;", 174 }, 
  { @"&macr;", 175 }, 
  { @"&deg;", 176 }, 
  { @"&plusmn;", 177 }, 
  { @"&sup2;", 178 }, 
  { @"&sup3;", 179 }, 
  { @"&acute;", 180 }, 
  { @"&micro;", 181 }, 
  { @"&para;", 182 }, 
  { @"&middot;", 183 }, 
  { @"&cedil;", 184 }, 
  { @"&sup1;", 185 }, 
  { @"&ordm;", 186 }, 
  { @"&raquo;", 187 }, 
  { @"&frac14;", 188 }, 
  { @"&frac12;", 189 }, 
  { @"&frac34;", 190 }, 
  { @"&iquest;", 191 }, 
  { @"&Agrave;", 192 }, 
  { @"&Aacute;", 193 }, 
  { @"&Acirc;", 194 }, 
  { @"&Atilde;", 195 }, 
  { @"&Auml;", 196 }, 
  { @"&Aring;", 197 }, 
  { @"&AElig;", 198 }, 
  { @"&Ccedil;", 199 }, 
  { @"&Egrave;", 200 }, 
  { @"&Eacute;", 201 }, 
  { @"&Ecirc;", 202 }, 
  { @"&Euml;", 203 }, 
  { @"&Igrave;", 204 }, 
  { @"&Iacute;", 205 }, 
  { @"&Icirc;", 206 }, 
  { @"&Iuml;", 207 }, 
  { @"&ETH;", 208 }, 
  { @"&Ntilde;", 209 }, 
  { @"&Ograve;", 210 }, 
  { @"&Oacute;", 211 }, 
  { @"&Ocirc;", 212 }, 
  { @"&Otilde;", 213 }, 
  { @"&Ouml;", 214 }, 
  { @"&times;", 215 }, 
  { @"&Oslash;", 216 }, 
  { @"&Ugrave;", 217 }, 
  { @"&Uacute;", 218 }, 
  { @"&Ucirc;", 219 }, 
  { @"&Uuml;", 220 }, 
  { @"&Yacute;", 221 }, 
  { @"&THORN;", 222 }, 
  { @"&szlig;", 223 }, 
  { @"&agrave;", 224 }, 
  { @"&aacute;", 225 }, 
  { @"&acirc;", 226 }, 
  { @"&atilde;", 227 }, 
  { @"&auml;", 228 }, 
  { @"&aring;", 229 }, 
  { @"&aelig;", 230 }, 
  { @"&ccedil;", 231 }, 
  { @"&egrave;", 232 }, 
  { @"&eacute;", 233 }, 
  { @"&ecirc;", 234 }, 
  { @"&euml;", 235 }, 
  { @"&igrave;", 236 }, 
  { @"&iacute;", 237 }, 
  { @"&icirc;", 238 }, 
  { @"&iuml;", 239 }, 
  { @"&eth;", 240 }, 
  { @"&ntilde;", 241 }, 
  { @"&ograve;", 242 }, 
  { @"&oacute;", 243 }, 
  { @"&ocirc;", 244 }, 
  { @"&otilde;", 245 }, 
  { @"&ouml;", 246 }, 
  { @"&divide;", 247 }, 
  { @"&oslash;", 248 }, 
  { @"&ugrave;", 249 }, 
  { @"&uacute;", 250 }, 
  { @"&ucirc;", 251 }, 
  { @"&uuml;", 252 }, 
  { @"&yacute;", 253 }, 
  { @"&thorn;", 254 }, 
  { @"&yuml;", 255 },
  
  // A.2.2. Special characters cont'd
  { @"&OElig;", 338 },
  { @"&oelig;", 339 },
  { @"&Scaron;", 352 },
  { @"&scaron;", 353 },
  { @"&Yuml;", 376 },

  // A.2.3. Symbols
  { @"&fnof;", 402 }, 

  // A.2.2. Special characters cont'd
  { @"&circ;", 710 },
  { @"&tilde;", 732 },
  
  // A.2.3. Symbols cont'd
  { @"&Alpha;", 913 }, 
  { @"&Beta;", 914 }, 
  { @"&Gamma;", 915 }, 
  { @"&Delta;", 916 }, 
  { @"&Epsilon;", 917 }, 
  { @"&Zeta;", 918 }, 
  { @"&Eta;", 919 }, 
  { @"&Theta;", 920 }, 
  { @"&Iota;", 921 }, 
  { @"&Kappa;", 922 }, 
  { @"&Lambda;", 923 }, 
  { @"&Mu;", 924 }, 
  { @"&Nu;", 925 }, 
  { @"&Xi;", 926 }, 
  { @"&Omicron;", 927 }, 
  { @"&Pi;", 928 }, 
  { @"&Rho;", 929 }, 
  { @"&Sigma;", 931 }, 
  { @"&Tau;", 932 }, 
  { @"&Upsilon;", 933 }, 
  { @"&Phi;", 934 }, 
  { @"&Chi;", 935 }, 
  { @"&Psi;", 936 }, 
  { @"&Omega;", 937 }, 
  { @"&alpha;", 945 }, 
  { @"&beta;", 946 }, 
  { @"&gamma;", 947 }, 
  { @"&delta;", 948 }, 
  { @"&epsilon;", 949 }, 
  { @"&zeta;", 950 }, 
  { @"&eta;", 951 }, 
  { @"&theta;", 952 }, 
  { @"&iota;", 953 }, 
  { @"&kappa;", 954 }, 
  { @"&lambda;", 955 }, 
  { @"&mu;", 956 }, 
  { @"&nu;", 957 }, 
  { @"&xi;", 958 }, 
  { @"&omicron;", 959 }, 
  { @"&pi;", 960 }, 
  { @"&rho;", 961 }, 
  { @"&sigmaf;", 962 }, 
  { @"&sigma;", 963 }, 
  { @"&tau;", 964 }, 
  { @"&upsilon;", 965 }, 
  { @"&phi;", 966 }, 
  { @"&chi;", 967 }, 
  { @"&psi;", 968 }, 
  { @"&omega;", 969 }, 
  { @"&thetasym;", 977 }, 
  { @"&upsih;", 978 }, 
  { @"&piv;", 982 }, 
 
  // A.2.2. Special characters cont'd
  { @"&ensp;", 8194 },
  { @"&emsp;", 8195 },
  { @"&thinsp;", 8201 },
  { @"&zwnj;", 8204 },
  { @"&zwj;", 8205 },
  { @"&lrm;", 8206 },
  { @"&rlm;", 8207 },
  { @"&ndash;", 8211 },
  { @"&mdash;", 8212 },
  { @"&lsquo;", 8216 },
  { @"&rsquo;", 8217 },
  { @"&sbquo;", 8218 },
  { @"&ldquo;", 8220 },
  { @"&rdquo;", 8221 },
  { @"&bdquo;", 8222 },
  { @"&dagger;", 8224 },
  { @"&Dagger;", 8225 },
    // A.2.3. Symbols cont'd  
  { @"&bull;", 8226 }, 
  { @"&hellip;", 8230 }, 
 
  // A.2.2. Special characters cont'd
  { @"&permil;", 8240 },
  
  // A.2.3. Symbols cont'd  
  { @"&prime;", 8242 }, 
  { @"&Prime;", 8243 }, 

  // A.2.2. Special characters cont'd
  { @"&lsaquo;", 8249 },
  { @"&rsaquo;", 8250 },

  // A.2.3. Symbols cont'd  
  { @"&oline;", 8254 }, 
  { @"&frasl;", 8260 }, 
  
  // A.2.2. Special characters cont'd
  { @"&euro;", 8364 },

  // A.2.3. Symbols cont'd  
  { @"&image;", 8465 },
  { @"&weierp;", 8472 }, 
  { @"&real;", 8476 }, 
  { @"&trade;", 8482 }, 
  { @"&alefsym;", 8501 }, 
  { @"&larr;", 8592 }, 
  { @"&uarr;", 8593 }, 
  { @"&rarr;", 8594 }, 
  { @"&darr;", 8595 }, 
  { @"&harr;", 8596 }, 
  { @"&crarr;", 8629 }, 
  { @"&lArr;", 8656 }, 
  { @"&uArr;", 8657 }, 
  { @"&rArr;", 8658 }, 
  { @"&dArr;", 8659 }, 
  { @"&hArr;", 8660 }, 
  { @"&forall;", 8704 }, 
  { @"&part;", 8706 }, 
  { @"&exist;", 8707 }, 
  { @"&empty;", 8709 }, 
  { @"&nabla;", 8711 }, 
  { @"&isin;", 8712 }, 
  { @"&notin;", 8713 }, 
  { @"&ni;", 8715 }, 
  { @"&prod;", 8719 }, 
  { @"&sum;", 8721 }, 
  { @"&minus;", 8722 }, 
  { @"&lowast;", 8727 }, 
  { @"&radic;", 8730 }, 
  { @"&prop;", 8733 }, 
  { @"&infin;", 8734 }, 
  { @"&ang;", 8736 }, 
  { @"&and;", 8743 }, 
  { @"&or;", 8744 }, 
  { @"&cap;", 8745 }, 
  { @"&cup;", 8746 }, 
  { @"&int;", 8747 }, 
  { @"&there4;", 8756 }, 
  { @"&sim;", 8764 }, 
  { @"&cong;", 8773 }, 
  { @"&asymp;", 8776 }, 
  { @"&ne;", 8800 }, 
  { @"&equiv;", 8801 }, 
  { @"&le;", 8804 }, 
  { @"&ge;", 8805 }, 
  { @"&sub;", 8834 }, 
  { @"&sup;", 8835 }, 
  { @"&nsub;", 8836 }, 
  { @"&sube;", 8838 }, 
  { @"&supe;", 8839 }, 
  { @"&oplus;", 8853 }, 
  { @"&otimes;", 8855 }, 
  { @"&perp;", 8869 }, 
  { @"&sdot;", 8901 }, 
  { @"&lceil;", 8968 }, 
  { @"&rceil;", 8969 }, 
  { @"&lfloor;", 8970 }, 
  { @"&rfloor;", 8971 }, 
  { @"&lang;", 9001 }, 
  { @"&rang;", 9002 }, 
  { @"&loz;", 9674 }, 
  { @"&spades;", 9824 }, 
  { @"&clubs;", 9827 }, 
  { @"&hearts;", 9829 }, 
  { @"&diams;", 9830 }
};

// Taken from http://www.w3.org/TR/xhtml1/dtds.html#a_dtd_Special_characters
// This is table A.2.2 Special Characters
static HTMLEscapeMap gUnicodeHTMLEscapeMap[] = {
  // C0 Controls and Basic Latin
  { @"&quot;", 34 },
  { @"&amp;", 38 },
  { @"&apos;", 39 },
  { @"&lt;", 60 },
  { @"&gt;", 62 },

  // Latin Extended-A
  { @"&OElig;", 338 },
  { @"&oelig;", 339 },
  { @"&Scaron;", 352 },
  { @"&scaron;", 353 },
  { @"&Yuml;", 376 },
  
  // Spacing Modifier Letters
  { @"&circ;", 710 },
  { @"&tilde;", 732 },
    
  // General Punctuation
  { @"&ensp;", 8194 },
  { @"&emsp;", 8195 },
  { @"&thinsp;", 8201 },
  { @"&zwnj;", 8204 },
  { @"&zwj;", 8205 },
  { @"&lrm;", 8206 },
  { @"&rlm;", 8207 },
  { @"&ndash;", 8211 },
  { @"&mdash;", 8212 },
  { @"&lsquo;", 8216 },
  { @"&rsquo;", 8217 },
  { @"&sbquo;", 8218 },
  { @"&ldquo;", 8220 },
  { @"&rdquo;", 8221 },
  { @"&bdquo;", 8222 },
  { @"&dagger;", 8224 },
  { @"&Dagger;", 8225 },
  { @"&permil;", 8240 },
  { @"&lsaquo;", 8249 },
  { @"&rsaquo;", 8250 },
  { @"&euro;", 8364 },
};


// Utility function for Bsearching table above
static int EscapeMapCompare(const void *ucharVoid, const void *mapVoid) {
  const unichar *uchar = (const unichar*)ucharVoid;
  const HTMLEscapeMap *map = (const HTMLEscapeMap*)mapVoid;
  int val;
  if (*uchar > map->uchar) {
    val = 1;
  } else if (*uchar < map->uchar) {
    val = -1;
  } else {
    val = 0;
  }
  return val;
}

@implementation NSString (GTMNSStringHTMLAdditions)
- (NSString *)gtm_stringByEscapingHTMLUsingTable:(HTMLEscapeMap*)table 
                                          ofSize:(NSUInteger)size 
                                 escapingUnicode:(BOOL)escapeUnicode {  
  NSUInteger length = [self length];
  if (!length) {
    return self;
  }
  
  NSMutableString *finalString = [NSMutableString string];
  NSMutableData *data2 = [NSMutableData dataWithCapacity:sizeof(unichar) * length];

  // this block is common between GTMNSString+HTML and GTMNSString+XML but
  // it's so short that it isn't really worth trying to share.
  const unichar *buffer = CFStringGetCharactersPtr((CFStringRef)self);
  if (!buffer) {
    // We want this buffer to be autoreleased.
    NSMutableData *data = [NSMutableData dataWithLength:length * sizeof(UniChar)];
    if (!data) {
      // COV_NF_START  - Memory fail case
      return nil;
      // COV_NF_END
    }
    [self getCharacters:[data mutableBytes]];
    buffer = [data bytes];
  }

  if (!buffer || !data2) {
    // COV_NF_START
    return nil;
    // COV_NF_END
  }
  
  unichar *buffer2 = (unichar *)[data2 mutableBytes];
  
  NSUInteger buffer2Length = 0;
  
  for (NSUInteger i = 0; i < length; ++i) {
    HTMLEscapeMap *val = bsearch(&buffer[i], table, 
                                 size / sizeof(HTMLEscapeMap), 
                                 sizeof(HTMLEscapeMap), EscapeMapCompare);
    if (val || (escapeUnicode && buffer[i] > 127)) {
      if (buffer2Length) {
        CFStringAppendCharacters((CFMutableStringRef)finalString, 
                                 buffer2, 
                                 buffer2Length);
        buffer2Length = 0;
      }
      if (val) {
        [finalString appendString:val->escapeSequence];
      }
      else {
        NSAssert(escapeUnicode && buffer[i] > 127, @"Illegal Character");
        [finalString appendFormat:@"&#%d;", buffer[i]];
      }
    } else {
      buffer2[buffer2Length] = buffer[i];
      buffer2Length += 1;
    }
  }
  if (buffer2Length) {
    CFStringAppendCharacters((CFMutableStringRef)finalString, 
                             buffer2, 
                             buffer2Length);
  }
  return finalString;
}

- (NSString *)gtm_stringByEscapingForHTML {
  return [self gtm_stringByEscapingHTMLUsingTable:gUnicodeHTMLEscapeMap 
                                           ofSize:sizeof(gUnicodeHTMLEscapeMap) 
                                  escapingUnicode:NO];
} // gtm_stringByEscapingHTML

- (NSString *)gtm_stringByEscapingForAsciiHTML {
  return [self gtm_stringByEscapingHTMLUsingTable:gAsciiHTMLEscapeMap 
                                           ofSize:sizeof(gAsciiHTMLEscapeMap) 
                                  escapingUnicode:YES];
} // gtm_stringByEscapingAsciiHTML

- (NSString *)gtm_stringByUnescapingFromHTML {
  NSRange range = NSMakeRange(0, [self length]);
  NSRange subrange = [self rangeOfString:@"&" options:NSBackwardsSearch range:range];
  
  // if no ampersands, we've got a quick way out
  if (subrange.length == 0) return self;
  NSMutableString *finalString = [NSMutableString stringWithString:self];
  do {
    NSRange semiColonRange = NSMakeRange(subrange.location, NSMaxRange(range) - subrange.location);
    semiColonRange = [self rangeOfString:@";" options:0 range:semiColonRange];
    range = NSMakeRange(0, subrange.location);
    // if we don't find a semicolon in the range, we don't have a sequence
    if (semiColonRange.location == NSNotFound) {
      continue;
    }
    NSRange escapeRange = NSMakeRange(subrange.location, semiColonRange.location - subrange.location + 1);
    NSString *escapeString = [self substringWithRange:escapeRange];
    NSUInteger length = [escapeString length];
    // a squence must be longer than 3 (&lt;) and less than 11 (&thetasym;)
    if (length > 3 && length < 11) {
      if ([escapeString characterAtIndex:1] == '#') {
        unichar char2 = [escapeString characterAtIndex:2];
        if (char2 == 'x' || char2 == 'X') {
          // Hex escape squences &#xa3;
          NSString *hexSequence = [escapeString substringWithRange:NSMakeRange(3, length - 4)];
          NSScanner *scanner = [NSScanner scannerWithString:hexSequence];
          unsigned value;
          if ([scanner scanHexInt:&value] && 
              value < USHRT_MAX &&
              value > 0 
              && [scanner scanLocation] == length - 4) {
            unichar uchar = (unichar)value;
            NSString *charString = [NSString stringWithCharacters:&uchar length:1];
            [finalString replaceCharactersInRange:escapeRange withString:charString];
          }

        } else {
          // Decimal Sequences &#123;
          NSString *numberSequence = [escapeString substringWithRange:NSMakeRange(2, length - 3)];
          NSScanner *scanner = [NSScanner scannerWithString:numberSequence];
          int value;
          if ([scanner scanInt:&value] && 
              value < USHRT_MAX &&
              value > 0 
              && [scanner scanLocation] == length - 3) {
            unichar uchar = (unichar)value;
            NSString *charString = [NSString stringWithCharacters:&uchar length:1];
            [finalString replaceCharactersInRange:escapeRange withString:charString];
          }
        }
      } else {
        // "standard" sequences
        for (unsigned i = 0; i < sizeof(gAsciiHTMLEscapeMap) / sizeof(HTMLEscapeMap); ++i) {
          if ([escapeString isEqualToString:gAsciiHTMLEscapeMap[i].escapeSequence]) {
            [finalString replaceCharactersInRange:escapeRange withString:[NSString stringWithCharacters:&gAsciiHTMLEscapeMap[i].uchar length:1]];
            break;
          }
        }
      }
    }
  } while ((subrange = [self rangeOfString:@"&" options:NSBackwardsSearch range:range]).length != 0);
  return finalString;
} // gtm_stringByUnescapingHTML
@end

/* }}} */

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

/* }}} */

/* Constants {{{ */

#define kPortoRootURL @"http://www.portoseguro.org.br/"

/* }}} */

/* Macros {{{ */

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

@interface GradesViewController : UIViewController {
	LoadingIndicatorView *$loadingView;
	NSMutableArray *$views;
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
		nil]];
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

@implementation NewsIndexViewController
@end

@implementation NewsItemView

static CTFramesetterRef CreateFramesetter(CTFontRef font, CGColorRef textColor, CFStringRef string, BOOL underlined) {
	if (string == NULL) string = (CFStringRef)@"";
	
	CGFloat spacing = 0.f;
	CTParagraphStyleSetting settings[1] = { kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(CGFloat), &spacing };
	CTParagraphStyleRef paragraphStyle = CTParagraphStyleCreate(settings, 1);
	
	int underline = underlined ? 1 : kCTUnderlineStyleNone;
	CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &underline);

	const CFStringRef attributeKeys[4] = { kCTFontAttributeName, kCTForegroundColorAttributeName, kCTParagraphStyleAttributeName, kCTUnderlineStyleAttributeName };
	const CFTypeRef attributeValues[4] = { font, textColor, paragraphStyle, number };
	CFDictionaryRef attributes = CFDictionaryCreate(NULL, (const void **)attributeKeys, (const void **)attributeValues, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

	CFAttributedStringRef attributedString = CFAttributedStringCreate(NULL, string, attributes);
	CFRelease(attributes);
	CFRelease(number);
	CFRelease(paragraphStyle);

	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(attributedString);
	
	//CFRelease(paragraphStyle);
	CFRelease(attributedString);

	return framesetter;
}

static CTFrameRef CreateFrame(CTFramesetterRef framesetter, CGRect rect) {
	CGPathRef path = CGPathCreateWithRect(rect, NULL);
	CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, NULL);

	CFRelease(path);
	return frame;
}

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

	bodyFramesetters = calloc([contents count], sizeof(CTFramesetterRef));
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
	return 6 * CTFontGetSize(bodyFont)*96/72; // don't ask me why. Just don't. I don't know.
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

		NSString *class = [[content attributes] objectForKey:@"class"];
		XMLElement *articleElement = [class hasSuffix:@"-2"] ? [content firstElementMatchingPath:@"./article"] : content;
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
	
	// XXX: Why is the text upside down?
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

@implementation GradesViewController
- (void)loadView {
	[super loadView];
	[[self view] setBackgroundColor:[UIColor whiteColor]];

	$loadingView = [[LoadingIndicatorView alloc] initWithFrame:[[self view] bounds]];
	[[self view] addSubview:$loadingView];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Notas"];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		SessionController *sessionController = [SessionController sharedInstance];
		
		NSURLResponse *response;
		NSError *error;
		
		NSURL *url = [NSURL URLWithString:[@"http://www.educacional.com.br/" stringByAppendingString:[[sessionController sessionInfo] objectForKey:kPortoPortalKey]]];
		NSData *data = [sessionController loadPageWithURL:url method:@"GET" response:&response error:&error];
		//NSLog(@"data: %@", data);
		
		XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:data];
		//NSLog(@"docccc: %@", document);
		XMLElement *root = [document firstElementMatchingPath:@"/html/body"];
		//NSLog(@"root %@", root);
		NSLog(@"content %@", [root content]);

		[document release];
	});
}

- (void)dealloc {
	[$loadingView release];

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
@end

/* }}} */

/* App Delegate {{{ */

@implementation AppDelegate
@synthesize window = $window;

- (void)applicationDidFinishLaunching:(UIApplication *)application {
	$window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	
	NewsViewController *newsViewController = [[[NewsViewController alloc] init] autorelease];
	UINavigationController *newsNavController = [[[UINavigationController alloc] initWithRootViewController:newsViewController] autorelease];
	[newsNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notícias" image:nil tag:0] autorelease]];
	
	GradesViewController *gradesViewController = [[[GradesViewController alloc] init] autorelease];
	UINavigationController *gradesNavController = [[[UINavigationController alloc] initWithRootViewController:gradesViewController] autorelease];
	[gradesNavController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Notas" image:nil tag:0] autorelease]];

	PapersViewController *papersViewController = [[[PapersViewController alloc] init] autorelease];
	[papersViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Circulares" image:nil tag:0] autorelease]];

	ServicesViewController *servicesViewController = [[[ServicesViewController alloc] init] autorelease];
	[servicesViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Serviços" image:nil tag:0] autorelease]];

	AccountViewController *accountViewController = [[[AccountViewController alloc] init] autorelease];
	[accountViewController setTabBarItem:[[[UITabBarItem alloc] initWithTitle:@"Conta" image:nil tag:0] autorelease]];

	NSArray *controllers = [NSArray arrayWithObjects:
		newsNavController,
		gradesNavController,
		papersViewController,
		servicesViewController,
		accountViewController,
		nil];
	$tabBarController = [[UITabBarController alloc] init];
	[$tabBarController setViewControllers:controllers];

	[[UINavigationBar appearance] setTintColor:UIColorFromHexWithAlpha(0x1c2956, 1.f)];

	[[SessionController sharedInstance] loadSessionWithHandler:^(BOOL unknown, NSError *error){}];

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
	
	InitCache();

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	int ret = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    
	[pool drain];
	return ret;
}

/* }}} */

/* }}} */

