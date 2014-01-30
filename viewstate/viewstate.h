// viewstate.h by Daniel Ferreira
// Public domain.

typedef struct type_ vsType;

typedef enum {
	kViewStateTypeUnknown,
	kViewStateTypeNull,
	kViewStateTypeByte,
	kViewStateTypeBoolean,
	kViewStateTypeInteger,
	kViewStateTypeChar,
	kViewStateTypeString,
	kViewStateTypeIndexedString,
	kViewStateTypeArray,
	kViewStateTypeStringArray,
	kViewStateTypeArrayList,
	kViewStateTypeEnum,
	kViewStateTypePair,
	kViewStateTypeTriplet,
	kViewStateTypeError
} vsStateType;

typedef struct {
	vsType **array;
	unsigned int length;
	unsigned int type;
} vsTypeArray;

typedef struct {
	int32_t value; // We ignore 64-bit values for now. Sorry.
	unsigned int type;
} vsTypeEnumValue;

typedef struct {
	vsType *first;
	vsType *second;
} vsPair;

typedef struct {
	vsType *first;
	vsType *second;
	vsType *third;
} vsTriplet;

typedef struct {
	vsPair *kvPairs;
} vsDictionary;

struct type_ {
	union {
		unsigned char byte;
		unsigned char boolean;
		
		int32_t integer;
		
		uint16_t character;
		char *string;
		char *indexedString;
		
		vsTypeArray *array;
		char **stringArray;
		vsType **arrayList;
		vsDictionary dictionary;

		vsTypeEnumValue enumValue;

		vsPair *pair;
		vsTriplet *triplet;

		int error;
	};

	vsStateType stateType;
};

#ifdef __cplusplus
extern "C" {
#endif
int base64_decode(const char *string, size_t len, char **output);

char *get_from_indexedstring_cache(int idx);
char *get_type_description(int type);

int32_t read_viewstate_int(unsigned char **viewState);
int read_type_format(unsigned char **viewState);

vsType *parse_viewstate(unsigned char **viewState, _Bool needsHeader);
#ifdef __cplusplus
}
#endif

