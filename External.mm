/* 

External code for PortoApp.
All copyrights are inside Bozo.m

*/

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
        keychainItemData = [[NSMutableDictionary alloc] init];
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
    NSMutableData *data = (NSMutableData *)context;
    [data appendBytes:buffer length:len];
    return len;
}

static int XMLElementOutputCloseCallback(void *context) {
    NSMutableData *data = (NSMutableData *)context;
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
    if (nodeName == NULL) nodeName = (char *)"";
    
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
        document = (xml ? xmlReadMemory : htmlReadMemory)((const char *)[data bytes], [data length], "", NULL, xml ? XML_PARSE_RECOVER : HTML_PARSE_NOWARNING | HTML_PARSE_NOERROR);
        
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

// Patch for iOS 7 thanks to http://www.blogosfera.co.uk/2013/06/abtableviewcell-issue-in-ios-7-with-drawcontentview-closed/
- (void)drawRect:(CGRect)rect {
    UIView *v = self;
    while (v && ![v isKindOfClass:[ABTableViewCell class]]) v = v.superview;
	[(ABTableViewCell *)v drawContentView:rect highlighted:NO];
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
	UIView *v = self;
    while (v && ![v isKindOfClass:[ABTableViewCell class]]) v = v.superview;
	[(ABTableViewCell *)v drawContentView:rect highlighted:NO];
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
	f.origin.y -= 1;
	f.size.height += 1;
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
    [self getCharacters:(unichar *)[data mutableBytes]];
    buffer = (const unichar *)[data bytes];
  }

  if (!buffer || !data2) {
    // COV_NF_START
    return nil;
    // COV_NF_END
  }
  
  unichar *buffer2 = (unichar *)[data2 mutableBytes];
  
  NSUInteger buffer2Length = 0;
  
  for (NSUInteger i = 0; i < length; ++i) {
    HTMLEscapeMap *val = (HTMLEscapeMap *)bsearch(&buffer[i], table,
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

