// Root module of nexlog. Access to library via reexports from nexlog.c3
module nexlog;

import core::types;

LogLevel lvl = LogLevel.INFO; // or whatever default value is appropriate

String levlel;


fn void test() {
	levlel = lvl.to_string();
}