#ifndef brightness_h
#define brightness_h

#include <stdio.h>
#include <stdbool.h>
#include <unistd.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <ApplicationServices/ApplicationServices.h>

bool getBrightness(CGDirectDisplayID dspy, io_service_t service, float *brightness);

bool setBrightness(CGDirectDisplayID dspy, io_service_t service, float brightness);

int getInternalDisplayIdAndService(CGDirectDisplayID* id, io_service_t* service);

#endif /* brightness_h */
