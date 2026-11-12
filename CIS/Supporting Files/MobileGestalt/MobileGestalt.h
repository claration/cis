//
//  MobileGestalt.h
//  CIS
//
//  Created by samsam on 11/12/26.
//

#ifndef CIS__MOBILE_GESTALT_H
#define CIS__MOBILE_GESTALT_H

#include <CoreFoundation/CoreFoundation.h>

CFPropertyListRef MGCopyAnswer(CFStringRef property);
static const CFStringRef kMGPhysicalHardwareNameString = CFSTR("PhysicalHardwareNameString");

#endif
