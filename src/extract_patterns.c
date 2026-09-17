#include <stdlib.h>
#include <stdio.h>
#include <expat.h>
#include <CoreFoundation/CoreFoundation.h>

#define PATH_TO_MAIN "common/main"
#define DEBUG 0

typedef struct patterns_xml_ctx_s {
    CFMutableArrayRef  patterns;
    CFStringRef        pattern_type;
    CFStringRef        pattern_count;
    CFMutableStringRef pattern_text;
    const char        *length_type;
    unsigned int       in_ldml:1;
    unsigned int       in_numbers:1;
    unsigned int       in_decimalFormats:1;
    unsigned int       in_decimalFormatLength:1;
    unsigned int       in_decimalFormat:1;
    unsigned int       in_pattern:1;
} patterns_xml_ctx_t;

static void patternsHandleXMLElementStart(void *userData, const XML_Char *name, const XML_Char **attrs) {
    patterns_xml_ctx_t *ctx = userData;
    if (strcasecmp(name, "ldml") == 0) {
        ctx->in_ldml = 1;
    }
    if (ctx->in_ldml && strcasecmp(name, "numbers") == 0) {
        ctx->in_numbers = 1;
    }
    if (ctx->in_numbers && strcasecmp(name, "decimalFormats") == 0) {
        for (int i=0; attrs[i]; i+=2) {
            if (strcasecmp(attrs[i], "numberSystem") == 0) {
                if (strcasecmp(attrs[i+1], "latn") == 0) {
                    ctx->in_decimalFormats = 1;
                }
                break;
            }
        }
    }
    if (ctx->in_decimalFormats && strcasecmp(name, "decimalFormatLength") == 0) {
        for (int i=0; attrs[i]; i+=2) {
            if (strcasecmp(attrs[i], "type") == 0) {
                if (strcasecmp(attrs[i+1], "short") == 0) {
                    ctx->in_decimalFormatLength = 1;
                }
                break;
            }
        }
    }
    if (ctx->in_decimalFormatLength && strcasecmp(name, "decimalFormat") == 0) {
        ctx->in_decimalFormat = 1;
    }
    if (ctx->in_decimalFormat && strcasecmp(name, "pattern") == 0) {
        for (int i=0; attrs[i]; i+=2) {
            if (strcasecmp(attrs[i], "type") == 0) {
                ctx->pattern_type = CFStringCreateWithCString(NULL, attrs[i+1], kCFStringEncodingUTF8);
            } else if (strcasecmp(attrs[i], "count") == 0) {
                ctx->pattern_count = CFStringCreateWithCString(NULL, attrs[i+1], kCFStringEncodingUTF8);
            }
        }
        if (ctx->pattern_type && ctx->pattern_count) {
            ctx->pattern_text = CFStringCreateMutable(NULL, 0);
            ctx->in_pattern = 1;
        }
    }
}

static void patternsClearPattern(patterns_xml_ctx_t *ctx) {
    if (ctx->pattern_type)
        CFRelease(ctx->pattern_type);
    if (ctx->pattern_count)
        CFRelease(ctx->pattern_count);
    if (ctx->pattern_text)
        CFRelease(ctx->pattern_text);
    ctx->pattern_type = NULL;
    ctx->pattern_count = NULL;
    ctx->pattern_text = NULL;
    ctx->in_pattern = 0;
}

static void patternsHandleXMLElementEnd(void *userData, const XML_Char *name) {
    patterns_xml_ctx_t *ctx = userData;
    if (ctx->in_decimalFormat && strcasecmp(name, "decimalFormat") == 0)
        ctx->in_decimalFormat = 0;
    if (ctx->in_decimalFormatLength && strcasecmp(name, "decimalFormatLength") == 0)
        ctx->in_decimalFormatLength = 0;
    if (ctx->in_decimalFormats && strcasecmp(name, "decimalFormats") == 0)
        ctx->in_decimalFormats = 0;
    if (ctx->in_numbers && strcasecmp(name, "numbers") == 0)
        ctx->in_numbers = 0;
    if (strcasecmp(name, "pattern") == 0) {
        /* "\u2191\u2191\u2191" marks a value inherited from the parent locale; skip it
         * so the formatter's own locale fallback supplies the pattern. */
        if (ctx->in_pattern &&
            CFStringCompare(ctx->pattern_text, CFSTR("\u2191\u2191\u2191"), 0) != kCFCompareEqualTo) {
            CFStringRef keys[3] = { CFSTR("pattern"), CFSTR("type"), CFSTR("count") };
            CFStringRef values[3] = { ctx->pattern_text, ctx->pattern_type, ctx->pattern_count };

            CFDictionaryRef pattern_info = CFDictionaryCreate(NULL,
                    (const void **)&keys,
                    (const void **)&values,
                    sizeof(keys)/sizeof(keys[0]),
                    &kCFTypeDictionaryKeyCallBacks,
                    &kCFTypeDictionaryValueCallBacks);

            CFArrayAppendValue(ctx->patterns, pattern_info);
            CFRelease(pattern_info);
        }
        /* Also frees a type or count read from a <pattern> that lacked the other attribute. */
        patternsClearPattern(ctx);
    }
}

static void patternsHandleXMLCharacterData(void *userData, const XML_Char *s, int len) {
    patterns_xml_ctx_t *ctx = userData;
    if (!ctx->in_pattern)
        return;

    /* expat may split one element's text across several calls (entity references,
     * buffer boundaries), so collect it and build the entry when the element ends. */
    CFStringRef chunk = CFStringCreateWithBytes(NULL, (const unsigned char *)s, len,
            kCFStringEncodingUTF8, false);
    if (chunk) {
        CFStringAppend(ctx->pattern_text, chunk);
        CFRelease(chunk);
    }
}

void usage() {
    fprintf(stderr, "Usage: extract_patterns <path/to/unicode/core>\n");
    exit(1);
}

int main(int argc, char *argv[]) {
    if (argc != 2)
        usage();

    char *path = argv[1];

    CFStringRef main_path;
    CFURLRef main_url;
    CFURLEnumeratorRef enumerator;
    CFMutableDictionaryRef patterns_dict;

    patterns_xml_ctx_t patterns_ctx;
    XML_Parser patterns_parser = XML_ParserCreate("UTF-8");

    main_path = CFStringCreateWithFormat(NULL, NULL, CFSTR("%s/%s"),
            path, PATH_TO_MAIN);

    main_url = CFURLCreateWithFileSystemPath(NULL, main_path, kCFURLPOSIXPathStyle, true);
    enumerator = CFURLEnumeratorCreateForDirectoryURL(NULL, main_url, 
            kCFURLEnumeratorSkipInvisibles, NULL);

    patterns_dict = CFDictionaryCreateMutable(NULL, 0, 
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

#if DEBUG
    fprintf(stderr, "Beginning enumeration\n");
#endif

    while (1) {
        CFURLEnumeratorResult result = kCFURLEnumeratorSuccess;
        CFURLRef file_url = NULL;
        CFErrorRef error = NULL;
        result = CFURLEnumeratorGetNextURL(enumerator, &file_url, &error);
        if (result == kCFURLEnumeratorEnd)
            break;

        if (result == kCFURLEnumeratorSuccess) {
            CFStringRef extension = CFURLCopyPathExtension(file_url);
            if (extension && CFStringCompare(extension, CFSTR("xml"), 0) == kCFCompareEqualTo) {
                CFStringRef path = CFURLCopyFileSystemPath(file_url, kCFURLPOSIXPathStyle);
                size_t path_len =  CFStringGetMaximumSizeOfFileSystemRepresentation(path);
                char *path_buf = malloc(path_len);
                CFStringGetFileSystemRepresentation(path, path_buf, path_len);

                memset(&patterns_ctx, 0, sizeof(patterns_xml_ctx_t));

                CFDataRef data = NULL;
                SInt32 errorCode = 0;
                int success = CFURLCreateDataAndPropertiesFromResource(
                        NULL, file_url, &data, NULL, NULL, &errorCode);

                if (!success) {
                    fprintf(stderr, "Error opening XML file: %s\n", path_buf);
                } else {
                    XML_ParserReset(patterns_parser, "UTF-8");
                    XML_SetStartElementHandler(patterns_parser, patternsHandleXMLElementStart);
                    XML_SetEndElementHandler(patterns_parser, patternsHandleXMLElementEnd);
                    XML_SetCharacterDataHandler(patterns_parser, patternsHandleXMLCharacterData);
                    XML_SetUserData(patterns_parser, &patterns_ctx);

                    patterns_ctx.patterns = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
                    patterns_ctx.length_type = "short";

#if DEBUG
                    fprintf(stderr, "Parsing URL: %s\n", path_buf);
#endif
                    int retval = XML_Parse(patterns_parser, (const char *)CFDataGetBytePtr(data), 
                            CFDataGetLength(data), 1);

                    if (retval == XML_STATUS_ERROR) {
                        fprintf(stderr, "Error parsing XML file: %s\n", path_buf);
                    } else if (CFArrayGetCount(patterns_ctx.patterns) > 0) {
                        CFURLRef no_ext_url = CFURLCreateCopyDeletingPathExtension(NULL, file_url);
                        CFStringRef basename = CFURLCopyLastPathComponent(no_ext_url);
                        CFDictionaryAddValue(patterns_dict, basename, patterns_ctx.patterns);
                        CFRelease(no_ext_url);
                        CFRelease(basename);
#if DEBUG
                        fprintf(stderr, "Found %ld patterns\n", CFArrayGetCount(patterns_ctx.patterns));
#endif
                    } else {
                    }

                    patternsClearPattern(&patterns_ctx);
                    CFRelease(patterns_ctx.patterns);
                    CFRelease(data);
                }

                free(path_buf);
                CFRelease(path);
            }
            if (extension)
                CFRelease(extension);
        } else if (result == kCFURLEnumeratorError) {
            CFDictionaryRef user_info = CFErrorCopyUserInfo(error);
            CFStringRef erroneous_path = CFDictionaryGetValue(user_info, CFSTR("NSFilePath"));
            size_t len =  CFStringGetMaximumSizeOfFileSystemRepresentation(erroneous_path);
            char *buf = malloc(len);
            CFStringGetFileSystemRepresentation(erroneous_path, buf, len);
            fprintf(stderr, "Error retrieving URL: %s\n", buf);
            free(buf);
            CFRelease(user_info);
        } else {
            fprintf(stderr, "Unknown CFURLEnumeratorGetNextURL result code: %ld\n",
                    result);
            break;
        }
    }

    CFRelease(main_path);
    CFRelease(main_url);
    CFRelease(enumerator);

    CFErrorRef plist_error = NULL;
    CFDataRef plist_data = CFPropertyListCreateData(NULL, patterns_dict, 
            kCFPropertyListXMLFormat_v1_0, 0, &plist_error);

    fwrite(CFDataGetBytePtr(plist_data), CFDataGetLength(plist_data), 1, stdout);

    fprintf(stderr, "Successfully parsed %ld files\n", CFDictionaryGetCount(patterns_dict));

    CFRelease(patterns_dict);

    XML_ParserFree(patterns_parser);
}
