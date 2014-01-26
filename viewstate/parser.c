/* parser.c
   A working ASP.NET New View State parser.
   Designed for Porto website view states. Unsure if fits other cases.

   Public domain.
*/

// Some special thanks go to "Reverse Engineering ASP .Net 2.0 View State", by Adam Pridgen
// http://www.thecoverofnight.com/presentations/aha2008/aha2008.pdf
// And as always, to the Bacon Team.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <inttypes.h>
#include <b64/cdecode.h>
#include "viewstate.h"

#define SHIFT_VIEWSTATE(v) (*((*v)++))

// Not my function, but I know what it's doing.
int base64_decode(const char *string, size_t len, char **output) {
	if (len < 1 || string == NULL) return -1;
	
	base64_decodestate s;
	size_t retlen;
	
	if ((*output = (char *)calloc((size_t)((double)len / (double)(4/3)) + 1, sizeof(unsigned char))) == NULL)
		return -1;
	printf("*output = %p\n", *output);
	
	base64_init_decodestate(&s);
	retlen = base64_decode_block(string, len, *output, &s);
	(*output)[retlen] = '\0';

	return retlen;
}

// Header
#define kUTF16Encoding 0xff // I'm unsure whether this means encoding. It's probably just some conclusion the pdf took.
#define kViewStateMagic 0x01

// Data types
#define kViewStateInteger 0x02			// 02 [intformat]
#define kViewStateByte 0x03			// 03 [byte]
#define kViewStateChar 0x04			// 04 [char]
#define kViewStateString 0x05			// 05 [intformat] [bytes]
#define kViewStateArray 0x14			// 14 [typespec] [len] [bytes]
#define kViewStateStringArray 0x15		// 15 [arraylen] [strlen] [bytes] ...
#define kViewStateArrayList 0x16		// 16 [len] [bytes]
#define kViewStateHybridDictionary 0x18		// 18 [len] [bytes]
#define kViewStateEnum 0x0b			// 0b [typespec] [value]
#define kViewStatePair 0x0f			// 0f
#define kViewStateTriplet 0x10			// 10
#define kViewStateIndexedString 0x1e		// 1e [len] [bytes]
#define kViewStateCachedIndexedString 0x1f	// 1f [index]
#define kViewStateWeirdArray 0x3c		// 3c [typespec] [wat(09)] [len] [wat(00)] [bytes] 08 [bytes]...

#define kViewStateNull 0x64
#define kViewStateEmptyString 0x65
#define kViewStateNumberZero 0x66
#define kViewStateBooleanTrue 0x67
#define kViewStateBooleanFalse 0x68

// Types
// Type Spec: 29 [len] [longtype] [stuff] || 2a [len] [shorttype] [stuff] || 2b [type] [stuff]
#define kViewStateLongTypeFlag 0x29
#define kViewStateShortTypeFlag 0x2a
#define kViewStateTypeNumberFlag 0x2b

#define kViewStateArrayTypeObject 0x00
#define kViewStateArrayTypeInt 0x01
#define kViewStateArrayTypeString 0x02 // But we have 0x15 if we want a string array. wat.
#define kViewStateArrayTypeBoolean 0x03

// Miscellanea
#define kViewStateNumberOfDefaultTypes 0x04
#define kViewStateWeirdArraySeparator 0x08

/* get_from_indexedstring_cache(int):
* Takes an index to get a value from the indexed string cache */
static char **indexedStringCache = NULL;
static unsigned int indexedStringCacheIndex = 0;

char *get_from_indexedstring_cache(int idx) {
	if (idx >= indexedStringCacheIndex) return NULL;
	return indexedStringCache[idx];
}

/* get_type_description(int):
* Takes a type and prints its description. I'm lazy to implement a hashtable. */
static char **typeDescriptionMap;
static unsigned int typeDescriptionMapIndex = 0;

char *get_type_description(int type) {
	if (type >= typeDescriptionMapIndex) return NULL;
	return typeDescriptionMap[type];
}

/* read_viewstate_int(unsigned char *):
* Takes the view state and moves on, returning the 32-bit int it finds using its int format. */
int32_t read_viewstate_int(unsigned char **viewState) {
	/*
	 The format works like:
	 0x0 ... 0x7f; when it reaches 0x80+, we get one more byte at its front: 0x1.
	 So we go up again from 0x80 to 0xff, and when we reach 256 the first byte gets back to 0x80 and the second goes to 0x2.
	 The same principle applies to 128*3=364: 0x80 0x3; 365: 0x81 0x3 and so on
	 When we reach 16384 (128^2), we get 0x80 0x80 0x1, and we move on.
	*/	
	
	// FIXME: Support 64-bit? Does viewstate allow that?
	unsigned char *startByte = *viewState;
	unsigned char *endByte = startByte;
	while (SHIFT_VIEWSTATE(viewState) >= 128) endByte++;

	int32_t value = (int32_t)*endByte;
	while (endByte != startByte) {
		value = value*128 + (*(--endByte) - 128);
	}
	
	return value;
}

/* read_type_format(unsigned char *):
* Takes the view state and moves on, returning its type number.
*/
int read_type_format(unsigned char **viewState) {
	unsigned char flag = SHIFT_VIEWSTATE(viewState);
	switch (flag) {
		// These two should be distinct, but in the end it comes down to the same thing.
		case kViewStateLongTypeFlag:
		case kViewStateShortTypeFlag: {
			int32_t len = read_viewstate_int(viewState);
			
			char *string = (char *)calloc(len, sizeof(char));
			typeDescriptionMap = (char **)realloc(typeDescriptionMap, (typeDescriptionMapIndex+1)*sizeof(char*));

			int32_t i;
			for (i=0; i<len; i++) {
				string[i] = SHIFT_VIEWSTATE(viewState);
			}
			string[i] = '\0';
			typeDescriptionMap[typeDescriptionMapIndex++] = string;

			return typeDescriptionMapIndex++;
		}

		case kViewStateTypeNumberFlag:
			return SHIFT_VIEWSTATE(viewState);

		default:
			fprintf(stderr, "UNKNOWN TYPE FLAG %d\n", flag);
			return -1;
	}
}


/* parse_viewstate(unsigned char *, _Bool)
* Takes a base64-decoded view state string and returns a type union with information.
*
* viewState is the view state string
* needsHeader defines whether we should check for file validity. */

/* Log Pass debug {{{ */
//#define LOG_PASS
#ifdef LOG_PASS
char tab[200];
static int _i=0;
#define ITAB tab[_i]='\t';tab[++_i]='\0';
#define ETAB tab[_i]='\t';tab[--_i]='\0';
#define LOG(...) {printf("%s",tab);printf(__VA_ARGS__);}
#else
#define ITAB
#define ETAB
#define LOG(...)
#endif
/* }}} */

vsType *parse_viewstate(unsigned char **viewState, _Bool needsHeader) {
	vsType *ret = (vsType *)malloc(sizeof(vsType));
	
	if (needsHeader) {
		printf("BYTE %d %d\n", *(*viewState), *((*viewState)+1));
        
        if (SHIFT_VIEWSTATE(viewState) != kUTF16Encoding) {
			ret->error = 1;
			ret->stateType = kViewStateTypeError;
			return ret;
		}
		if (SHIFT_VIEWSTATE(viewState) != kViewStateMagic) {
			ret->error = 1;
			ret->stateType = kViewStateTypeError;
			return ret;
		}

		// Initialize type map with standard view state types.
		typeDescriptionMap = (char **)calloc(4, sizeof(char *));
		typeDescriptionMap[kViewStateArrayTypeObject] = "System.Object";
		typeDescriptionMap[kViewStateArrayTypeInt] = "System.Int32";
		typeDescriptionMap[kViewStateArrayTypeString] = "System.String";
		typeDescriptionMap[kViewStateArrayTypeBoolean] = "System.Boolean";
		typeDescriptionMapIndex = kViewStateNumberOfDefaultTypes;
	}
	
	switch (SHIFT_VIEWSTATE(viewState)) {
		case kViewStateInteger: {
			int32_t integer = read_viewstate_int(viewState);
			ret->integer = integer;
			ret->stateType = kViewStateTypeInteger;
			
			LOG("INT: %d\n", integer);
			break;
		}

		case kViewStateByte: {
			unsigned char byte = SHIFT_VIEWSTATE(viewState);
			ret->byte = byte;
			ret->stateType = kViewStateTypeByte;
			
			LOG("BYTE: %d\n", byte);
			break;
		}

		case kViewStateChar: {
			// TODO!
			ret->character = 0;
			ret->stateType = kViewStateTypeChar;
			
			//LOG("CHAR: %c\n", ret->character);
			LOG("CHAR: Unimplemented.\n");
			break;
		}

		case kViewStateString: {
			int32_t len = read_viewstate_int(viewState);
			// This is a weird encoding. Can the char type hold this?
			char *string = (char *)calloc(len+1, sizeof(char));
			
			int32_t i;
			for (i=0; i<len; i++) {
				string[i] = SHIFT_VIEWSTATE(viewState);
			}
			string[i] = '\0';

			ret->string = string;
			ret->stateType = kViewStateTypeString;
			
			LOG("STRING(len=%d): %s\n", len, string);
			break;
		}

		case kViewStateArray: {
			int typ = read_type_format(viewState);
			int32_t len = read_viewstate_int(viewState);
			vsType **values = (vsType **)calloc(len, sizeof(vsType *));
			
			LOG("ARRAY: %d\n", typ);
			ITAB;
			int32_t i;
			for (i=0; i<len; i++) {
				values[i] = parse_viewstate(viewState, false);
			}
			ETAB;
			
			ret->array = (vsTypeArray *)malloc(sizeof(vsTypeArray));
			ret->array->array = values;
			ret->array->type = typ;
			ret->array->length = len;
			ret->stateType = kViewStateTypeArray;
			break;
		}
		
		case kViewStateWeirdArray: {
			int typ = read_type_format(viewState);
			SHIFT_VIEWSTATE(viewState); // Unknown byte 1
			int32_t len = read_viewstate_int(viewState);
			SHIFT_VIEWSTATE(viewState); // Unknown byte 2

			vsType **values = (vsType **)calloc(len, sizeof(vsType *));
			
			LOG("WEIRD_ARRAY: %d (len = %d)\n", typ, len);
			ITAB;
			int32_t i;
			for (i=0; i<len; i++) {
				values[i] = parse_viewstate(viewState, false);
				if (i+1 != len && SHIFT_VIEWSTATE(viewState) != kViewStateWeirdArraySeparator) {
					ret->error = 2;
					ret->stateType = kViewStateTypeError;
					return ret;
				}
			}
			ETAB;
            
            ret->array = (vsTypeArray *)malloc(sizeof(vsTypeArray));
			ret->array->array = values;
			ret->array->type = typ;
			ret->array->length = len;
			ret->stateType = kViewStateTypeArray;
			break;
	
		}

		case kViewStateStringArray: {
			int32_t len = read_viewstate_int(viewState);
			char **strings = (char **)calloc(len, sizeof(char *)); // BUG BUG BUG
			
			LOG("STRING ARRAY\n");
			ITAB;
			int32_t i;
			for (i=0; i<len; i++) {
				int32_t slen = read_viewstate_int(viewState);
				char *string = (char *)calloc(slen, sizeof(char));
				
				int32_t j;
				for (j=0; j<slen; j++) {
					string[j] = SHIFT_VIEWSTATE(viewState);
				}
				strings[i] = string;
			}
			ETAB;

			ret->stringArray = strings;
			ret->stateType = kViewStateTypeStringArray;
			break;
		}

		case kViewStateArrayList: {
			int32_t len = read_viewstate_int(viewState);
			vsType **list = (vsType **)calloc(len, sizeof(vsType *));
			
			LOG("ARRAY LIST\n");
			ITAB;
			int32_t i;
			for (i=0; i<len; i++) {
				list[i] = parse_viewstate(viewState, false);
			}
			ETAB;

			ret->arrayList = list;
			ret->stateType = kViewStateTypeArrayList;
			break;
		}

		case kViewStateEnum: {
			int typ = read_type_format(viewState);
			ret->enumValue.value = read_viewstate_int(viewState);
			ret->enumValue.type = typ;
			ret->stateType = kViewStateTypeEnum;
		
			LOG("ENUM(%d): %d\n", typ, ret->enumValue.value);
			break;
		}

		case kViewStatePair: {
			LOG("PAIR\n");
			ITAB;
			ret->pair = (vsPair *)malloc(sizeof(vsPair));
            
			ret->pair->first = parse_viewstate(viewState, false);
			ret->pair->second = parse_viewstate(viewState, false);
			ETAB;

			ret->stateType = kViewStateTypePair;
			break;
		}

		case kViewStateTriplet: {
			LOG("TRIPLET\n");
			ITAB;
			ret->triplet = (vsTriplet *)malloc(sizeof(vsTriplet));
			ret->triplet->first = parse_viewstate(viewState, false);
			ret->triplet->second = parse_viewstate(viewState, false);
			ret->triplet->third = parse_viewstate(viewState, false);
			ETAB;

			ret->stateType = kViewStateTypeTriplet;
			break;
		}

		case kViewStateHybridDictionary: {
			int32_t len = read_viewstate_int(viewState);
			ret->dictionary.kvPairs = (vsPair *)calloc(len, sizeof(vsPair));
			
			LOG("HYBRID DICTIONARY\n");
			ITAB;
			int32_t i;
			for (i=0; i<len; i++) {
				ret->dictionary.kvPairs[i].first = parse_viewstate(viewState, false);
				ret->dictionary.kvPairs[i].second = parse_viewstate(viewState, false);
			}
			ETAB;

			break;
		}

		case kViewStateIndexedString: {
			int32_t len = read_viewstate_int(viewState);

			indexedStringCache = (char **)realloc(indexedStringCache, (indexedStringCacheIndex+1) * sizeof(char*));
			
			char *string = (char *)calloc(len, sizeof(char));//indexedStringCache[indexedStringCacheIndex++];
			int32_t i;
			for (i=0; i<len; i++) {
				string[i] = SHIFT_VIEWSTATE(viewState);
			}
			string[i] = '\0';
			indexedStringCache[indexedStringCacheIndex++] = string;
			
			ret->indexedString = string;
			ret->stateType = kViewStateTypeIndexedString;

			LOG("INDEXED STRING: %s\n", string);
			break;
		}

		case kViewStateCachedIndexedString: {
			int32_t index = read_viewstate_int(viewState);
			ret->indexedString = indexedStringCache[index];
			ret->stateType = kViewStateTypeIndexedString;

			LOG("CACHED INDEXED STRING: %s\n", indexedStringCache[index]);
			break;
		}

		case kViewStateNull: {
			ret->byte = 0;
			ret->stateType = kViewStateTypeNull;

			LOG("NULL\n");
			break;
		}

		case kViewStateEmptyString: {
			ret->string = "";
			ret->stateType = kViewStateTypeString;

			LOG("STRING: <empty>\n");
			break;
		}

		case kViewStateNumberZero: {
			ret->integer = 0;
			ret->stateType = kViewStateTypeInteger;

			LOG("INTEGER ZERO\n");
			break;
		}

		case kViewStateBooleanTrue: {
			ret->boolean = true;
			ret->stateType = kViewStateTypeBoolean;

			LOG("TRUE\n");
			break;
		}

		case kViewStateBooleanFalse: {
			ret->boolean = false;
			ret->stateType = kViewStateTypeBoolean;
            
			LOG("FALSE\n");
			break;
		}

		case 0xf3: {
			LOG("ERRONEOUS DATA. INVALID VIEW STATE.\n");
			ret->error = 3;
			ret->stateType = kViewStateTypeError;
			break;
		}

		default: {
			printf("UNKNOWN BYTE %d! Please make sure the view state is valid or report an issue at http://github.com/theiostream/viewstate.\n", *((*viewState)-1));
			break;
		}
	}

	return ret;
}

/*static char fcontent[1048576];
int main(int argc, char **argv) {
	FILE *f = fopen(argv[1], "r");
	fread(fcontent, sizeof(char), 1048576, f);
	fclose(f);
	
	char *bozo = NULL;
	int ll = base64_decode(fcontent, strlen(fcontent), &bozo);
	if (ll < 0) return 1;

	FILE *db = fopen("./debug.txt", "w");
	fwrite(bozo, sizeof(char), ll, db);
	fclose(db);

	printf("====== VIEW STATE PARSER by Daniel Ferreira; Public Domain. ======\n");
	vsType *t = parse_viewstate((unsigned char **)&bozo, true);

	return 0;
}*/
