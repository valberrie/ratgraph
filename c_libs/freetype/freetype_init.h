#include <ft2build.h>
#define FT_CONFIG_OPTION_SUBPIXEL_RENDERING
#include <freetype/freetype.h>
#include <freetype/ftlcdfil.h>

  #undef FTERRORS_H_
  #define FT_ERRORDEF( e, v, s )  { e,  s },
  #define FT_ERROR_START_LIST     {
  #define FT_ERROR_END_LIST       { 0, NULL } };

  struct ErrorType{
    int          err_code;
    const char*  err_msg;
  } ;

struct ErrorType ft_errors[] =

  #include <freetype/fterrors.h>

