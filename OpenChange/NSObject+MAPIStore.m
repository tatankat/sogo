/* NSObject+MAPIStore.m - this file is part of SOGo
 *
 * Copyright (C) 2011-2012 Inverse inc
 *
 * Author: Wolfgang Sourdeau <wsourdeau@inverse.ca>
 *
 * This file is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This file is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSThread.h>
#import <NGExtensions/NSObject+Logs.h>

#import "MAPIStorePropertySelectors.h"
#import "MAPIStoreTypes.h"
#import "NSArray+MAPIStore.h"
#import "NSData+MAPIStore.h"
#import "NSDate+MAPIStore.h"
#import "NSValue+MAPIStore.h"
#import "NSString+MAPIStore.h"

#import "NSObject+MAPIStore.h"

#undef DEBUG
#include <mapistore/mapistore.h>
#include <mapistore/mapistore_errors.h>

@implementation NSObject (MAPIStoreTallocHelpers)

static int
MAPIStoreTallocWrapperDestroy (void *data)
{
  struct MAPIStoreTallocWrapper *wrapper;
  NSAutoreleasePool *pool;

//  GSRegisterCurrentThread ();
  pool = [NSAutoreleasePool new];
  wrapper = data;
  //NSLog (@"destroying wrapped object (wrapper: %p; object: %p (%@))...\n", wrapper, wrapper->instance, NSStringFromClass([wrapper->instance class]));
  [wrapper->instance release];
  [pool release];
//  GSUnregisterCurrentThread ();

  return 0;
}

- (struct MAPIStoreTallocWrapper *) tallocWrapper: (TALLOC_CTX *) tallocCtx
{
  struct MAPIStoreTallocWrapper *wrapper;

  wrapper = talloc_zero (tallocCtx, struct MAPIStoreTallocWrapper);
  talloc_set_destructor ((void *) wrapper, MAPIStoreTallocWrapperDestroy);
  wrapper->instance = self;
  [self retain];
  //NSLog (@"returning wrapper: %p; object: %p (%@)", wrapper, self, NSStringFromClass([self class]));
  return wrapper;
}

@end

@implementation NSObject (MAPIStoreDataTypes)

- (int) getValue: (void **) data
          forTag: (enum MAPITAGS) propTag
        inMemCtx: (TALLOC_CTX *) memCtx
{
  uint16_t valueType;
  int rc = MAPISTORE_SUCCESS;

  // [self logWithFormat: @"property %.8x found", propTag];
  valueType = (propTag & 0xffff);
  switch (valueType)
    {
    case PT_NULL:
      *data = NULL;
      break;
    case PT_SHORT:
      *data = [(NSNumber *) self asShortInMemCtx: memCtx];
      break;
    case PT_LONG:
      *data = [(NSNumber *) self asLongInMemCtx: memCtx];
      break;
    case PT_I8:
      *data = [(NSNumber *) self asI8InMemCtx: memCtx];
      break;
    case PT_BOOLEAN:
      *data = [(NSNumber *) self asBooleanInMemCtx: memCtx];
      break;
    case PT_DOUBLE:
      *data = [(NSNumber *) self asDoubleInMemCtx: memCtx];
      break;
    case PT_UNICODE:
    case PT_STRING8:
      *data = [(NSString *) self asUnicodeInMemCtx: memCtx];
      break;
    case PT_SYSTIME:
      *data = [(NSCalendarDate * ) self asFileTimeInMemCtx: memCtx];
      break;
    case PT_BINARY:
    case PT_SVREID:
      *data = [(NSData *) self asBinaryInMemCtx: memCtx];
      break;
    case PT_CLSID:
      *data = [(NSData *) self asGUIDInMemCtx: memCtx];
      break;
    case PT_MV_LONG:
      *data = [(NSArray *) self asMVLongInMemCtx: memCtx];
      break;
    case PT_MV_UNICODE:
      *data = [(NSArray *) self asMVUnicodeInMemCtx: memCtx];
      break;
    case PT_MV_BINARY:
      *data = [(NSArray *) self asMVBinaryInMemCtx: memCtx];
      break;

    default:
      [self errorWithFormat: @"object type not handled: %d (0x%.4x)",
            valueType, valueType];
      abort();
      *data = NULL;
      rc = MAPISTORE_ERR_NOT_FOUND;
    }

  return rc;
}

/* helper getters */
- (int) getEmptyString: (void **) data inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = [@"" asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

- (int) getLongZero: (void **) data inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = MAPILongValue (memCtx, 0);

  return MAPISTORE_SUCCESS;
}

- (int) getYes: (void **) data inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = MAPIBoolValue (memCtx, YES);

  return MAPISTORE_SUCCESS;
}

- (int) getNo: (void **) data inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = MAPIBoolValue (memCtx, NO);

  return MAPISTORE_SUCCESS;
}

- (int) getSMTPAddrType: (void **) data inMemCtx: (TALLOC_CTX *) memCtx
{
  *data = [@"SMTP" asUnicodeInMemCtx: memCtx];

  return MAPISTORE_SUCCESS;
}

@end

@implementation NSObject (MAPIStoreProperties)

+ (enum mapistore_error) getAvailableProperties: (struct SPropTagArray **) propertiesP
                                       inMemCtx: (TALLOC_CTX *) memCtx
{
  struct SPropTagArray *properties;
  const MAPIStorePropertyGetter *classGetters;
  NSUInteger count;
  enum MAPITAGS propTag;
  uint16_t propId;

  properties = talloc_zero (memCtx, struct SPropTagArray);
  properties->aulPropTag = talloc_array (properties, enum MAPITAGS,
                                         MAPIStoreSupportedPropertiesCount);
  classGetters = MAPIStorePropertyGettersForClass (self);
  for (count = 0; count < MAPIStoreSupportedPropertiesCount; count++)
    {
      propTag = MAPIStoreSupportedProperties[count];
      propId = (propTag >> 16) & 0xffff;
      if (classGetters[propId])
        {
          properties->aulPropTag[properties->cValues] = propTag;
          properties->cValues++;
        }
    }

  *propertiesP = properties;

  return MAPISTORE_SUCCESS;
}

+ (void) fillAvailableProperties: (struct SPropTagArray *) properties
                  withExclusions: (BOOL *) exclusions
{
  TALLOC_CTX *localMemCtx;
  struct SPropTagArray *subProperties;
  uint16_t propId;
  NSUInteger count;
  
  localMemCtx = talloc_zero (NULL, TALLOC_CTX);
  [self getAvailableProperties: &subProperties inMemCtx: localMemCtx];
  for (count = 0; count < subProperties->cValues; count++)
    {
      propId = (subProperties->aulPropTag[count] >> 16) & 0xffff;
      if (!exclusions[propId])
        {
          properties->aulPropTag[properties->cValues]
            = subProperties->aulPropTag[count];
          properties->cValues++;
          exclusions[propId] = YES;
        }
    }
  talloc_free (localMemCtx);
}

- (enum mapistore_error) getAvailableProperties: (struct SPropTagArray **) propertiesP
                                       inMemCtx: (TALLOC_CTX *) memCtx
{
  NSUInteger count;
  struct SPropTagArray *availableProps;
  enum MAPITAGS propTag;

  availableProps = talloc_zero (memCtx, struct SPropTagArray);
  availableProps->aulPropTag = talloc_array (availableProps, enum MAPITAGS,
                                             MAPIStoreSupportedPropertiesCount);
  for (count = 0; count < MAPIStoreSupportedPropertiesCount; count++)
    {
      propTag = MAPIStoreSupportedProperties[count];
      if ([self canGetProperty: propTag])
        {
          availableProps->aulPropTag[availableProps->cValues] = propTag;
          availableProps->cValues++;
        }
    }

  *propertiesP = availableProps;

  return MAPISTORE_SUCCESS;  
}

- (BOOL) canGetProperty: (enum MAPITAGS) propTag
{
  uint16_t propId;
  const IMP *classGetters;

  classGetters = (IMP *) MAPIStorePropertyGettersForClass (isa);
  propId = (propTag >> 16) & 0xffff;

  return (classGetters[propId] != NULL);
}

@end
