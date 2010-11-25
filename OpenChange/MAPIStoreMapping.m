/* MAPIStoreMapping.m - this file is part of SOGo
 *
 * Copyright (C) 2010 Inverse inc.
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

#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#import <NGExtensions/NSObject+Logs.h>

#import "MAPIStoreMapping.h"

// static const uint64_t idIncrement = 0x010000; /* we choose a high enough id to avoid any clash with system folders */
// static uint64_t idCounter = 0x200001;

@implementation MAPIStoreMapping

+ (id) sharedMapping
{
  static id sharedMapping = nil;

  if (!sharedMapping)
    sharedMapping = [self new];

  return sharedMapping;
}

- (id) init
{
  if ((self = [super init]))
    {
      mapping = [NSMutableDictionary new];
      reverseMapping = [NSMutableDictionary new];
    }

  return self;
}

- (void) dealloc
{
  [mapping release];
  [reverseMapping release];
  [super dealloc];
}

- (NSString *) urlFromID: (uint64_t) idNbr
{
  NSNumber *key;
  
  key = [NSNumber numberWithUnsignedLongLong: idNbr];
  
  return [mapping objectForKey: key];
}

- (uint64_t) idFromURL: (NSString *) url
{
  NSNumber *idKey;
  uint64_t idNbr;
  
  idKey = [reverseMapping objectForKey: url];
  if (idKey)
    idNbr = [idKey unsignedLongLongValue];
  else
    idNbr = NSNotFound;

  return idNbr;
}

- (BOOL) registerURL: (NSString *) urlString
              withID: (uint64_t) idNbr
{
  NSNumber *idKey;
  BOOL rc;

  idKey = [NSNumber numberWithUnsignedLongLong: idNbr];
  if ([mapping objectForKey: idKey]
      || [reverseMapping objectForKey: urlString])
    {
      [self errorWithFormat: @"attempt to double register an entry ('%@', %lld)",
            urlString, idNbr];
      rc = NO;
    }
  else
    {
      [mapping setObject: urlString forKey: idKey];
      [reverseMapping setObject: idKey forKey: urlString];
      rc = YES;
      [self logWithFormat: @"registered url '%@' with id %lld (0x%.8x)",
            urlString, idNbr, (uint32_t) idNbr];
    }

  return rc;
}

@end
