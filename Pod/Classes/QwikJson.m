//
//  QwikJson.m
//  EZWaves
//
//  Created by Logan Sease on 11/19/14.
//  Copyright (c) 2014 Qonceptual. All rights reserved.
//

#import "QwikJson.h"
#import <objc/runtime.h>


@implementation QwikJson

/*
 * create a test object. This is used by the test data service. override this in your subclass
 */
+(id)testObject
{
    id object = [[[self class] alloc] init];
    return object;
}

+(id)objectWithId:(NSString*)newId
{
    QwikJson * object = [[[self class] alloc] init];
    
    SEL selector = NSSelectorFromString(@"setId:");
    if([object respondsToSelector:selector])
    {
        [object setValue:newId forKey:@"id"];
    }
    return object;
}


#pragma mark setup

+(NSDictionary<NSString*,NSString*>*)apiToObjectMapping;
{
    //this should be overridden in the subclass
    return nil;
}

#pragma mark serialization Helpers

/**
 * Override this in your subclasses to allow for any special data types to be set into the object,
 * This is necessary for any date fields
 * for example if([key isEqualToString:@"date"]) [self setDateValue:value forKey:key];
 * make sure you call the super method if you are not handling this yourself!
 */
-(void)setValue:(id)value forKey:(NSString *)key
{
    @try{
    //remove any null values
    if([value isKindOfClass:[NSArray class]])
    {
        NSMutableArray * newArray = [NSMutableArray array];
        for(NSObject * obj in (NSArray*)value)
        {
            if(obj != nil && ![obj isKindOfClass:[NSNull class]])
            {
                [newArray addObject:obj];
            }
        }
        
        [super setValue:newArray forKey:key];
    }
    else{
        [super setValue:value forKey:key];
    }
    }
    @catch(NSException * e)
    {
        if([self respondsToSelector:NSSelectorFromString(key)])
        {
            NSLog(@"Error Setting %@: %@", key, e);
        }
    }
    
}


/**
 * override this method in your subclasses to define the class types for any relationships
 * and example would read like: if ([key isEqualToString:@"user"] return [EZWUser class];
 */
+(Class)classForKey:(NSString*)key
{
    return nil;
}

#pragma mark nscoding serialization
- (void)encodeWithCoder:(NSCoder *)encoder {
    //Encode properties, other class variables, etc
    //[encoder encodeObject:self.question forKey:@"question"];
    
    unsigned count;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    
    for (int i = 0; i < count; i++) {
        NSString *key = [NSString stringWithUTF8String:property_getName(properties[i])];
        [self encode:encoder propertyNamed:key];
    }
    
}

//override this in your base class to seralize a special property
-(void)encode:(NSCoder*)encoder propertyNamed:(NSString*)key{
    
    //check for a string output values for our custom db types
    //first see if this is one of our custom property types. If so, then convert it to a string before we save it
    Class objectClass = [[self class ]classForKey:key];
    if(objectClass != nil && [objectClass respondsToSelector:@selector(objectFromDbString:)] && [self valueForKey:key]&& [self valueForKey:key] != [NSNull null])
    {
        NSObject<DBField> * object = [self valueForKey:key];
        [self setValue:[object toDbFormattedString] forKey:key];
    }
    else{
        [encoder encodeObject:[self valueForKey:key] forKey:key];
    }
}


- (id)initWithCoder:(NSCoder *)decoder {
    if(self = [super init]) {
        //decode properties, other class vars
        //self.question = [decoder decodeObjectForKey:@"question"];
        unsigned count;
        objc_property_t *properties = class_copyPropertyList([self class], &count);
        
        for (int i = 0; i < count; i++) {
            NSString *key = [NSString stringWithUTF8String:property_getName(properties[i])];
            [self decode:decoder propertyNamed:key];
        }
        
    }
    return self;
}

//override this in your baseclass to deserialize a special property
-(void)decode:(NSCoder*)decoder propertyNamed:(NSString*)key
{
    //first see if this is one of our custom property types. If so, then convert it to from string before we load it
    Class objectClass = [[self class ]classForKey:key];
    if(objectClass != nil && [objectClass respondsToSelector:@selector(objectFromDbString:)] && [decoder  decodeObjectForKey:key] != [NSNull null])
    {
        [self setValue:[objectClass objectFromDbString:[decoder decodeObjectForKey:key]] forKey:key];
    }
    else{
        [self setValue:[decoder decodeObjectForKey:key] forKey:key];
    }
}

-(void)writeToPreferencesWithKey:(NSString*)key
{
    NSDictionary * serialized = [self toDictionary];
    NSString * json = [serialized toJsonString];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:json forKey:key];
    [defaults synchronize];
}

+(id)readFromPrefencesWithKey:(NSString*)key
{
    id object = nil;
    @try {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *encodedObject = [defaults objectForKey:key];
        NSDictionary * dictionary = [NSDictionary fromJsonString:encodedObject];
        object = [[self class] objectFromDictionary:dictionary];
    }
    @catch (NSException *exception) {}
    
    return object;
}

#pragma mark standard serialization

/**
 * turn this object into a dictionary so it may be turned into json and passed into the api
 */
-(NSDictionary*)toDictionary
{
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    unsigned count;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    
    for (int i = 0; i < count; i++) {
        NSString *key = [NSString stringWithUTF8String:property_getName(properties[i])];
        [self addProperty:key toDictionary:dict];
    }
    
    free(properties);
    
    return [NSDictionary dictionaryWithDictionary:dict];
    
}

//This method is used by the toDictionary method. Override this in your subclass to customize the json / dictionary
//serialization for specific properties
-(void)addProperty:(NSString*)key toDictionary:(NSMutableDictionary*)dict
{
    //see if we need to rename our key
    NSDictionary * nameMappings = [[self class]apiToObjectMapping];
    NSString * renamedKey = key;
    if([nameMappings.allValues containsObject:key])
    {
        renamedKey = [nameMappings allKeysForObject:key].firstObject;
    }
    
    //if this object is a serializable object, serialize it and add it to the dictionary
    if([[self valueForKey:key] respondsToSelector:@selector(toDictionary)])
    {
        [self serializeObject:[[self valueForKey:key]toDictionary] withKey:renamedKey toDictionary:dict];
    }
    
    //if this is an array of db objects that is not empty then serialize the array and set it
    else if([[self valueForKey:key] isKindOfClass:[NSArray class]] && ((NSArray*)[self valueForKey:key]).count > 0 && [((NSArray*)[self valueForKey:key])[0] respondsToSelector:@selector(toDictionary)])
    {
        NSMutableArray * serializedArray = [NSMutableArray array];
        NSArray * nonSerializedArray = [self valueForKey:key];
        for(QwikJson * nonSerializedObject in nonSerializedArray)
        {
            [serializedArray addObject:[nonSerializedObject toDictionary]];
        }
        [self serializeObject:serializedArray withKey:renamedKey toDictionary:dict];
    }
    
    //if this is a specialized dbField object as defined by implementing the dbField protocol, such as DBDate
    //use the protocol conversion methods to convert and save the value
    else if([[self valueForKey:key] respondsToSelector:@selector(toDbFormattedString)])
    {
        [self serializeObject:[[self valueForKey:key]toDbFormattedString]  withKey:renamedKey toDictionary:dict];
    }
    
    //otherwise just set it
    else if([self valueForKey:key])
    {
        [self serializeObject:[self valueForKey:key] withKey:renamedKey toDictionary:dict];
    }
}

//this exists so that a subclass might override this and specify a new key or perform some custom action.
-(void)serializeObject:(NSObject*)object withKey:(NSString*)key toDictionary:(NSMutableDictionary*)dictionary
{
    @try{
    [dictionary setObject:object forKey:key];
    }
    @catch(NSException * e)
    {
        NSLog(@"Error Setting %@: %@",key,e);
    }
}


/**
 * turn this object into a dictionary and then into a json data string through standard json serialization
 */
- (NSData*)toJSONData
{
    
    NSDictionary * dict = [self toDictionary];
    
    NSError *error = nil;
    NSData *json;
    
    // Dictionary convertable to JSON ?
    if ([NSJSONSerialization isValidJSONObject:dict])
    {
        // Serialize the dictionary
        json = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
        
        // If no errors, let's view the JSON
        if (json != nil && error == nil)
        {
            NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
            
            NSLog(@"JSON: %@", jsonString);
        }
    }
    
    return json;
}



/**
 * parse a single object of this given type from an input dictionary. This is used to instanciate an object
 * from the results of an api call
 */
+(id)objectFromDictionary:(NSDictionary*)inputDictionary
{
    @try{
        QwikJson* object = [[[self class] alloc] init];
    
        for(NSString * key in inputDictionary.allKeys)
        {
            [object writeObjectFrom:inputDictionary forKey:key toProperty:key];
        }
        return object;
    }
    @catch(NSException*e)
    {
        return nil;
    }
}


/**
 Handles writing of one property from an input dictionary into the object
 OVERRIDE this to manually control the writing process for a specific property in your subclass
 */
-(void)writeObjectFrom:(NSDictionary*)inputDictionary forKey:(NSString*)key toProperty:(NSString*)property
{
    
    //see if we need to rename our key
    NSDictionary * nameMappings = [[self class]apiToObjectMapping];
    NSString * renamedKey = key;
    if([nameMappings.allKeys containsObject:key])
    {
        renamedKey = [nameMappings valueForKey:key];
    }
    
    //determine the type of object we are going to be setting
    Class objectClass = [[self class] classForKey:renamedKey];
    
    @try {
        
        //NSObject * value = [inputDictionary objectForKey:key];
        
        //if this is a dictionary it is a foreign key associated object
        //so parse that object and then set it
        if(objectClass != nil && [[inputDictionary objectForKey:key]isKindOfClass:[NSDictionary class]])
        {
            QwikJson * subObject = [objectClass objectFromDictionary:[inputDictionary objectForKey:key]];
            [self setValue:subObject forKey:renamedKey];
        }
        
        //if this is an array then parse that object array and set it
        else if(objectClass != nil && [[inputDictionary objectForKey:key]isKindOfClass:[NSArray class]])
        {
            NSArray * jsonArray = [inputDictionary objectForKey:key];
            NSArray * objectArray = [[self class] arrayForJsonArray:jsonArray ofClass:objectClass];
            [self setValue:objectArray forKey:renamedKey];
        }
        
        //if this is a specific dbField type then parse this using the dbField parsing protocol
        else if(objectClass != nil && [objectClass respondsToSelector:@selector(objectFromDbString:)] && [inputDictionary objectForKey:key] != [NSNull null])
        {
            id valueObject = [objectClass objectFromDbString:[inputDictionary objectForKey:key]];
            if(valueObject)
            {
                [self setValue:valueObject forKey:renamedKey];
            }
        }
        
        //if this is supposed to be an NSString, but the api is returning it as an NSNumber, convert it to a string
        //this happens in the case of the id field
        else if(objectClass == [NSString class] && [[inputDictionary valueForKey:key] isKindOfClass:[NSNumber class]])
        {
            NSNumber * idNumber = [inputDictionary valueForKey:key];
            [self setValue:[idNumber stringValue] forKey:renamedKey];
        }
        
        //if this is supposed to be an NSNumber, but the api is returning it as an NSString, convert it to a NSNumber
        else if(objectClass == [NSNumber class] && [[inputDictionary valueForKey:key] isKindOfClass:[NSString class]])
        {
            NSString * idString = [inputDictionary valueForKey:key];
            NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
            f.numberStyle = NSNumberFormatterDecimalStyle;
            [self setValue:[f numberFromString:idString]  forKey:renamedKey];
        }
        
        //otherwise, this is just a standard setter method, so set the value
        else{
            if(![[inputDictionary valueForKey:key] isEqual:[NSNull null]])
            {
                [self setValue:[inputDictionary valueForKey:key] forKey:renamedKey];
            }
            else
            {
                [self setValue:nil forKey:renamedKey];
            }
        }
        
    }
    @catch (NSException *exception) {
        //swallow the exception. No need for tons of logging. This will happen if the property doesn't have a setter,
        //which can be common
        //NSLog(@"There was an error parsing %@ with key %@, error = %@",[objectClass description], key, exception.description);
    }

}

/**
 * parse a single object from a NSData object, which is can be formed from a json string
 */
+ (QwikJson*)objectFromJSON:(NSData *)objectNotation error:(NSError **)error
{
    NSError *localError = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:objectNotation
                                                         options:0
                                                           error:&localError];
    
    if (localError != nil)
    {
        *error = localError;
        return nil;
    }
    
    QwikJson* object = [[self class] objectFromDictionary:dict];
    
    if (localError != nil)
    {
        *error = localError;
        return nil;
    }
    
    return object;
}


/**
 * turn a json array object that has been returned from the api into an object array of the given object
 * type
 */
+(NSArray*)arrayForJsonArray:(NSArray*)inputArray ofClass:(Class)parseClass
{
    NSMutableArray * array = [NSMutableArray array];
    
    for(NSObject * object in inputArray)
    {
        if([object isKindOfClass:[NSDictionary class]])
        {
            NSDictionary * objectDict = (NSDictionary*)object;
            QwikJson * object = [parseClass objectFromDictionary:objectDict];
            if(object)
            {
                [array addObject:object];
            }
        }
        else if([object isKindOfClass:[NSArray class]])
        {
            NSArray * jsonArray = (NSArray*)object;
            NSArray * objectArray = [self arrayForJsonArray:jsonArray ofClass:parseClass];
            if(objectArray)
            {
                [array addObject:objectArray];
            }
        }
    }
    return array;
}

//convert from an array of models to an array of dictionaries
+(NSArray*)jsonArrayFromArray:(NSArray*)inputArray ofClass:(Class)modelClass
{
    NSMutableArray * dictionaryArray = [NSMutableArray array];
    for(QwikJson * jsonable in inputArray)
    {
        NSDictionary * dict = [jsonable toDictionary];
        if(dict)
        {
            [dictionaryArray addObject:dict];
        }
    }
    return dictionaryArray;
}

//a custom comparitor to compare ID field for model classes when available
- (BOOL)isEqual:(id)other {
    if (other == self)
        return YES;
    if (!other || ![other isKindOfClass:[self class]])
        return NO;
    
    SEL selector = NSSelectorFromString(@"id");
    if([self respondsToSelector:selector] && [other respondsToSelector:selector])
    {
        return [[self valueForKey:@"id"] isEqual:[other valueForKey:@"id"]];
    }
    return [super isEqual:other];
}


@end



#pragma mark DB Field Implementations
//this class represents a date time formatted like 2015-01-01T10:15:30 in UTC
@implementation DBDateTime

static NSString * dbDateTimeFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

+(void)setDateFormat:(NSString*)format
{
    dbDateTimeFormat = format;
}

+(id)objectFromDbString:(NSString*)dbString
{
    NSDateFormatter * formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:dbDateTimeFormat];
    //[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDate * date = [formatter dateFromString:dbString];
    DBDateTime * dbDate = [[DBDateTime alloc]initWithDate:date];
    return dbDate;
}
-(NSString*)toDbFormattedString
{
    NSDateFormatter * formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:dbDateTimeFormat];
    //[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    return [formatter stringFromDate:self.date];
}
-(NSString*)displayString
{
    NSDateFormatter * displayFormatter = [[NSDateFormatter alloc]init];
    [displayFormatter setDateFormat:@"M/dd/yyyy h:mm a"];
    return [displayFormatter stringFromDate:self.date];
}

-(id)initWithDate:(NSDate*)date
{
    if([super init] && date)
    {
        self.date = date;
        return self;
    }
    return nil;
}

-(id)initWithDBDate:(DBDate*)dbDate andDBTime:(DBTime*)dbTime
{
    NSDateFormatter * dateFormatter = [[NSDateFormatter alloc]init];
    [dateFormatter setDateFormat:@"MM/dd/yyyy"];
    
    NSDateFormatter * timeFormatter = [[NSDateFormatter alloc]init];
    [timeFormatter setDateFormat:@"HH:mm:ss"];
    
    NSString * combinedString = [NSString stringWithFormat:@"%@ %@",[dateFormatter stringFromDate:dbDate.date],[timeFormatter stringFromDate:dbTime.date]];
    
    NSDateFormatter * combinedFormatter = [[NSDateFormatter alloc]init];
    [combinedFormatter setDateFormat:@"MM/dd/yyyy HH:mm:ss"];
    
    NSDate * combinedDate = [combinedFormatter dateFromString:combinedString];
    
    return [self initWithDate:combinedDate];
}


@end

//this class represents a date formatted like 2015-MM-DD
@implementation DBDate
static NSString * dbDateFormat = @"yyyy-MM-dd";

+(void)setDateFormat:(NSString*)format
{
    dbDateFormat = format;
}

+(id)objectFromDbString:(NSString*)dbString
{
    NSDateFormatter * formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:dbDateFormat];
    NSDate * date = [formatter dateFromString:dbString];
    DBDate * dbDate = [[DBDate alloc]initWithDate:date];
    return dbDate;
}
-(NSString*)toDbFormattedString
{
    NSDateFormatter * formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:dbDateFormat];
    return [formatter stringFromDate:self.date];
}
-(NSString*)displayString
{
    NSDateFormatter * displayFormatter = [[NSDateFormatter alloc]init];
    [displayFormatter setDateFormat:@"M/dd/yyyy"];
    return [displayFormatter stringFromDate:self.date];
}

-(id)initWithDate:(NSDate*)date
{
    if([super init] && date)
    {
        self.date = date;
        return self;
    }
    return nil;
}

@end

//this class represents a time formatted "HH:MM:SS" in UTC
@implementation DBTime

static NSString * dbTimeFormat = @"HH:mm:ss";

+(void)setDateFormat:(NSString*)format
{
    dbTimeFormat = format;
}

+(id)objectFromDbString:(NSString*)dbString
{
    NSDateFormatter * formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:dbTimeFormat];
    //[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDate * date = [formatter dateFromString:dbString];
    DBTime * dbDate = [[DBTime alloc]initWithDate:date];
    return dbDate;
}
-(NSString*)toDbFormattedString
{
    NSDateFormatter * formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:dbTimeFormat];
    //[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    return [formatter stringFromDate:self.date];
}
-(NSString*)displayString
{
    NSDateFormatter * displayFormatter = [[NSDateFormatter alloc]init];
    [displayFormatter setDateFormat:@"h:mm a"];
    return [displayFormatter stringFromDate:self.date];
}
-(id)initWithDate:(NSDate*)date
{
    if([super init] && date)
    {
        self.date = date;
        return self;
    }
    return nil;
}

@end

//this class represents a time stamp formatted like 14128309481 in UTC
@implementation DBTimeStamp
+(id)objectFromDbString:(NSString*)dbString
{
    if ((dbString == nil) || ([dbString isEqual:[NSNull null]])) return nil;
    NSDate * date = [[NSDate alloc] initWithTimeIntervalSince1970:[dbString doubleValue] * 0.001f];
    
    //convert to local time
    //NSTimeZone *tz = [NSTimeZone defaultTimeZone];
    //NSInteger seconds = [tz secondsFromGMTForDate: date];
    NSDate * newDate = date;//[NSDate dateWithTimeInterval: seconds sinceDate: date];
    DBTimeStamp * dbDate = [[DBTimeStamp alloc]initWithDate:newDate];
    return dbDate;
}
-(NSString*)toDbFormattedString
{
    //NSTimeZone *tz = [NSTimeZone defaultTimeZone];
    //NSInteger seconds = -[tz secondsFromGMTForDate: self.date];
    //NSDate * utcDate = [NSDate dateWithTimeInterval: seconds sinceDate: self.date];
    
    NSTimeInterval interval = [self.date timeIntervalSince1970];//[utcDate timeIntervalSince1970];
    NSString *string = [NSString stringWithFormat:@"%.0f", interval * 1000.0f];
    return string;
}
-(NSString*)displayString
{
    NSDateFormatter * displayFormatter = [[NSDateFormatter alloc]init];
    [displayFormatter setDateFormat:@"h:mm a"];
    return [displayFormatter stringFromDate:self.date];
}
-(id)initWithDate:(NSDate*)date
{
    if([super init] && date)
    {
        self.date = date;
        return self;
    }
    return nil;
}

@end

