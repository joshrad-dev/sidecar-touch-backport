#import <Foundation/Foundation.h>
#import <objc/message.h>

static const NSInteger SCTDisplayCapabilitiesMask = 2;

static id SCTCallObject(id object, SEL selector) {
	if (!object || ![object respondsToSelector:selector]) {
		return nil;
	}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	return [object performSelector:selector];
#pragma clang diagnostic pop
}

static id SCTPatchedSidecarObject(id object, id type) {
	if (![type isKindOfClass:NSString.class] || ![(NSString *)type isEqualToString:@"config"]) {
		return object;
	}

	if (![object isKindOfClass:NSDictionary.class]) {
		return object;
	}

	NSMutableDictionary *patched = [(NSDictionary *)object mutableCopy];
	patched[@"displayCapabilities"] = @(SCTDisplayCapabilitiesMask);
	return patched;
}

static id SCTPatchedSidecarItems(id items) {
	if (![items respondsToSelector:@selector(count)] || ![items respondsToSelector:@selector(objectAtIndex:)]) {
		return items;
	}

	Class itemClass = NSClassFromString(@"SidecarItem");
	if (!itemClass) {
		return items;
	}

	NSMutableArray *patchedItems = nil;
	NSUInteger count = [items count];
	for (NSUInteger i = 0; i < count; i++) {
		id item = [items objectAtIndex:i];
		id type = SCTCallObject(item, @selector(type));
		if (![type isKindOfClass:NSString.class] || ![(NSString *)type isEqualToString:@"config"]) {
			continue;
		}

		id objectValue = SCTCallObject(item, @selector(objectValue));
		id patchedObject = SCTPatchedSidecarObject(objectValue, type);
		if (patchedObject == objectValue) {
			continue;
		}

		id (*initWithObjectAndType)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
		id newItem = initWithObjectAndType([itemClass alloc], @selector(initWithObject:type:), patchedObject, type);
		if (!newItem) {
			continue;
		}

		if (!patchedItems) {
			patchedItems = [items mutableCopy];
		}
		patchedItems[i] = newItem;
	}

	return patchedItems ?: items;
}

%hook SidecarRequest

- (void)sendItems:(id)items {
	%orig(SCTPatchedSidecarItems(items));
}

- (void)sendItems:(id)items complete:(id)complete {
	%orig(SCTPatchedSidecarItems(items), complete);
}

%end

%hook SidecarItem

- (id)initWithObject:(id)object type:(id)type {
	return %orig(SCTPatchedSidecarObject(object, type), type);
}

%end

/*
 Debug probes kept here for future investigation.

 To re-enable, move the needed helpers/hooks back into active code and add the
 required imports:

 #import <UIKit/UIKit.h>
 #import <objc/runtime.h>
 #import <dlfcn.h>
 #import <substrate.h>

 Logging helpers:

 static NSString *SCTProcessName(void) {
 	return NSProcessInfo.processInfo.processName ?: @"<unknown>";
 }

 static NSString *SCTBundleID(void) {
 	return NSBundle.mainBundle.bundleIdentifier ?: @"<none>";
 }

 static void SCTLog(NSString *format, ...) {
 	va_list args;
 	va_start(args, format);
 	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
 	va_end(args);

 	NSLog(@"[SidecarTouch] [%@/%@] %@", SCTProcessName(), SCTBundleID(), message);
 }

 static NSString *SCTPointString(CGPoint point) {
 	return [NSString stringWithFormat:@"{%.2f, %.2f}", point.x, point.y];
 }

 static NSString *SCTRectString(CGRect rect) {
 	return [NSString stringWithFormat:@"{%.2f, %.2f, %.2f, %.2f}", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
 }

 static NSString *SCTHexString(const uint8_t *bytes, NSUInteger length, NSUInteger maxLength) {
 	if (!bytes || length == 0) {
 		return @"";
 	}

 	NSUInteger count = MIN(length, maxLength);
 	NSMutableString *hex = [NSMutableString stringWithCapacity:count * 3];
 	for (NSUInteger i = 0; i < count; i++) {
 		if (i > 0) {
 			[hex appendString:@" "];
 		}
 		[hex appendFormat:@"%02x", bytes[i]];
 	}
 	if (count < length) {
 		[hex appendFormat:@" ... +%lu", (unsigned long)(length - count)];
 	}
 	return hex;
 }

 static NSString *SCTCompactHexString(NSData *data) {
 	return SCTHexString((const uint8_t *)data.bytes, data.length, 2048);
 }

 static void SCTLogDataChunks(NSString *label, NSData *data) {
 	const uint8_t *bytes = (const uint8_t *)data.bytes;
 	NSUInteger length = data.length;
 	NSUInteger chunkSize = 48;

 	for (NSUInteger offset = 0; offset < length; offset += chunkSize) {
 		NSUInteger count = MIN(chunkSize, length - offset);
 		SCTLog(@"%@ offset=%lu length=%lu data=%@",
 			label,
 			(unsigned long)offset,
 			(unsigned long)count,
 			SCTHexString(bytes + offset, count, count));
 	}
 }

 static NSString *SCTObjectSummary(id object) {
 	if (!object) {
 		return @"<nil>";
 	}

 	return [NSString stringWithFormat:@"<%@ %p> %@", NSStringFromClass([object class]), object, object];
 }

 static void SCTLogClassSurface(NSString *className) {
 	Class cls = NSClassFromString(className);
 	if (!cls) {
 		SCTLog(@"surface %@ missing", className);
 		return;
 	}

 	unsigned int methodCount = 0;
 	Method *methods = class_copyMethodList(cls, &methodCount);
 	NSMutableArray<NSString *> *methodNames = [NSMutableArray arrayWithCapacity:methodCount];
 	for (unsigned int i = 0; i < methodCount; i++) {
 		[methodNames addObject:NSStringFromSelector(method_getName(methods[i]))];
 	}
 	free(methods);

 	unsigned int ivarCount = 0;
 	Ivar *ivars = class_copyIvarList(cls, &ivarCount);
 	NSMutableArray<NSString *> *ivarNames = [NSMutableArray arrayWithCapacity:ivarCount];
 	for (unsigned int i = 0; i < ivarCount; i++) {
 		const char *name = ivar_getName(ivars[i]);
 		[ivarNames addObject:name ? @(name) : @"<nil>"];
 	}
 	free(ivars);

 	SCTLog(@"surface %@ methods=%@ ivars=%@", className, methodNames, ivarNames);
 }

 static void SCTLogSidecarItems(NSString *label, id items) {
 	SCTLog(@"%@ summary=%@", label, SCTObjectSummary(items));

 	if (![items respondsToSelector:@selector(count)] || ![items respondsToSelector:@selector(objectAtIndex:)]) {
 		return;
 	}

 	NSUInteger count = [items count];
 	for (NSUInteger i = 0; i < count; i++) {
 		id item = [items objectAtIndex:i];
 		id type = SCTCallObject(item, @selector(type));
 		id uniformType = SCTCallObject(item, @selector(uniformType));
 		id objectValue = SCTCallObject(item, @selector(objectValue));
 		id data = SCTCallObject(item, @selector(data));

 		SCTLog(@"%@[%lu] item=%@ type=%@ uniformType=%@ objectValue=%@ dataClass=%@ dataLength=%@ data=%@",
 			label,
 			(unsigned long)i,
 			SCTObjectSummary(item),
 			type,
 			uniformType,
 			objectValue,
 			data ? NSStringFromClass([data class]) : @"<nil>",
 			[data respondsToSelector:@selector(length)] ? @([data length]) : nil,
 			[data isKindOfClass:NSData.class] ? SCTCompactHexString(data) : data);

 		if ([data isKindOfClass:NSData.class] && [data length] > 96) {
 			SCTLogDataChunks([NSString stringWithFormat:@"%@[%lu] dataChunk", label, (unsigned long)i], data);
 		}
 	}
 }

 static void SCTLogOPACKPayload(id opack) {
 	SCTLog(@"SidecarStream OPACK summary=%@", SCTObjectSummary(opack));

 	if (![opack respondsToSelector:@selector(enumerateKeysAndObjectsUsingBlock:)]) {
 		return;
 	}

 	[(NSDictionary *)opack enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
 		(void)stop;
 		if ([value isKindOfClass:NSData.class]) {
 			NSData *data = value;
 			const uint8_t *bytes = (const uint8_t *)data.bytes;
 			SCTLog(@"SidecarStream OPACK key=%@ dataLength=%lu reportID=0x%02x data=%@",
 				key,
 				(unsigned long)data.length,
 				data.length > 0 ? bytes[0] : 0,
 				SCTCompactHexString(data));
 			if (data.length > 96) {
 				SCTLogDataChunks([NSString stringWithFormat:@"SidecarStream OPACK key=%@ chunk", key], data);
 			}
 		} else {
 			SCTLog(@"SidecarStream OPACK key=%@ value=%@", key, SCTObjectSummary(value));
 		}
 	}];
 }

 static void SCTLogTouchSet(NSString *label, NSSet<UITouch *> *touches, UIEvent *event, UIView *view) {
 	NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:touches.count];

 	for (UITouch *touch in touches) {
 		CGPoint viewPoint = view ? [touch locationInView:view] : CGPointZero;
 		CGPoint windowPoint = touch.window ? [touch locationInView:touch.window] : CGPointZero;
 		[parts addObject:[NSString stringWithFormat:@"phase=%ld taps=%lu type=%ld view=%@ window=%@ major=%.2f force=%.3f",
 			(long)touch.phase,
 			(unsigned long)touch.tapCount,
 			(long)touch.type,
 			SCTPointString(viewPoint),
 			SCTPointString(windowPoint),
 			touch.majorRadius,
 			touch.force]];
 	}

 	SCTLog(@"%@ count=%lu event=%@ touches=[%@]",
 		label,
 		(unsigned long)touches.count,
 		event,
 		[parts componentsJoinedByString:@"; "]);
 }

 Debug hooks:

 %hook UIApplication
 - (void)sendEvent:(UIEvent *)event {
 	NSSet<UITouch *> *touches = event.allTouches;
 	if (touches.count > 0) {
 		SCTLogTouchSet(@"UIApplication sendEvent", touches, event, nil);
 	}
 	%orig;
 }
 %end

 %hook SidecarStream
 - (void)sendItems:(id)items complete:(id)complete {
 	SCTLog(@"SidecarStream sendItems self=%@ items=%@", SCTObjectSummary(self), SCTObjectSummary(items));
 	SCTLogSidecarItems(@"SidecarStream sendItems", items);
 	%orig;
 }

 - (void)sendOPACK:(id)opack completion:(id)completion {
 	SCTLog(@"SidecarStream sendOPACK self=%@ opack=%@", SCTObjectSummary(self), SCTObjectSummary(opack));
 	SCTLogOPACKPayload(opack);
 	%orig;
 }
 %end

 %hook SidecarItem
 - (id)initWithData:(NSData *)data type:(id)type {
 	SCTLog(@"SidecarItem initWithData type=%@ dataLength=%@ data=%@",
 		type,
 		[data respondsToSelector:@selector(length)] ? @([data length]) : nil,
 		[data isKindOfClass:NSData.class] ? SCTCompactHexString(data) : data);
 	if ([data isKindOfClass:NSData.class] && data.length > 96) {
 		SCTLogDataChunks(@"SidecarItem initWithData chunk", data);
 	}
 	id value = %orig;
 	SCTLog(@"SidecarItem initWithData -> %@", SCTObjectSummary(value));
 	return value;
 }
 %end

 %hook DisplayMainViewController
 - (void)receivedItems:(id)items {
 	SCTLogSidecarItems(@"DisplayMainViewController receivedItems", items);
 	%orig;
 }
 %end

 %hook DisplayViewController
 - (void)viewDidLoad {
 	SCTLog(@"DisplayViewController viewDidLoad self=%@", self);
 	%orig;
 }

 - (void)setDisplayView:(UIView *)view {
 	SCTLog(@"DisplayViewController setDisplayView=%@ frame=%@ bounds=%@ multi=%d gestures=%lu",
 		view,
 		SCTRectString(view.frame),
 		SCTRectString(view.bounds),
 		view.multipleTouchEnabled,
 		(unsigned long)view.gestureRecognizers.count);
 	%orig;
 }
 %end

 %hook _TtC17ContinuityDisplay15TouchController
 - (id)init {
 	SCTLog(@"TouchController init");
 	id value = %orig;
 	SCTLog(@"TouchController init -> %@", value);
 	return value;
 }

 - (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
 	BOOL result = %orig;
 	SCTLog(@"TouchController shouldReceiveTouch recognizer=%@ touchType=%ld phase=%ld location=%@ -> %d",
 		recognizer,
 		(long)touch.type,
 		(long)touch.phase,
 		SCTPointString([touch locationInView:touch.view]),
 		result);
 	return result;
 }

 - (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
 	BOOL result = %orig;
 	SCTLog(@"TouchController simultaneous recognizer=%@ other=%@ -> %d", recognizer, other, result);
 	return result;
 }

 - (void)pencilInteractionDidTap:(id)interaction {
 	SCTLog(@"TouchController pencilInteractionDidTap=%@", interaction);
 	%orig;
 }
 %end

 %hook _TtC17ContinuityDisplay21SidecarDisplaySession
 - (id)init {
 	SCTLog(@"SidecarDisplaySession init");
 	id value = %orig;
 	SCTLog(@"SidecarDisplaySession init -> %@", value);
 	return value;
 }

 - (void)sidecarRequest:(id)request receivedItems:(id)items {
 	SCTLog(@"SidecarDisplaySession receivedItems request=%@ items=%@", request, items);
 	SCTLogSidecarItems(@"SidecarDisplaySession receivedItems", items);
 	%orig;
 }
 %end

 %hook _TtC17ContinuityDisplay16HIDEventObserver
 - (id)init {
 	SCTLog(@"HIDEventObserver init");
 	id value = %orig;
 	SCTLog(@"HIDEventObserver init -> %@", value);
 	return value;
 }
 %end

 %hook _TtC17ContinuityDisplay16DisplayHIDDevice
 - (id)init {
 	SCTLog(@"DisplayHIDDevice init");
 	id value = %orig;
 	SCTLog(@"DisplayHIDDevice init -> %@", value);
 	return value;
 }
 %end

 static int (*orig_IOHIDUserDeviceHandleReport)(void *device, uint8_t *report, long reportLength);

 static int replaced_IOHIDUserDeviceHandleReport(void *device, uint8_t *report, long reportLength) {
 	SCTLog(@"IOHIDUserDeviceHandleReport device=%p length=%ld reportID=0x%02x bytes=%@",
 		device,
 		reportLength,
 		reportLength > 0 && report ? report[0] : 0,
 		SCTHexString(report, reportLength > 0 ? (NSUInteger)reportLength : 0, 96));
 	return orig_IOHIDUserDeviceHandleReport(device, report, reportLength);
 }

 %ctor {
 	SCTLog(@"loaded");

 	NSArray<NSString *> *classNames = @[
 		@"DisplayViewController",
 		@"DisplayMainViewController",
 		@"SidecarDisplayConfig",
 		@"SidecarItem",
 		@"SidecarRequest",
 		@"SidecarStream",
 		@"_TtC17ContinuityDisplay15TouchController",
 		@"_TtC17ContinuityDisplay16HIDEventObserver",
 		@"_TtC17ContinuityDisplay16DisplayHIDDevice",
 		@"_TtC17ContinuityDisplay21SidecarDisplaySession"
 	];

 	for (NSString *className in classNames) {
 		SCTLog(@"class %@ present=%d", className, NSClassFromString(className) != Nil);
 	}

 	for (NSString *className in @[@"SidecarDisplayConfig", @"SidecarItem", @"SidecarRequest", @"SidecarStream", @"DisplayMainViewController", @"_TtC17ContinuityDisplay21SidecarDisplaySession"]) {
 		SCTLogClassSurface(className);
 	}

 	void *handleReport = dlsym(RTLD_DEFAULT, "IOHIDUserDeviceHandleReport");
 	if (handleReport) {
 		MSHookFunction(handleReport, (void *)replaced_IOHIDUserDeviceHandleReport, (void **)&orig_IOHIDUserDeviceHandleReport);
 		SCTLog(@"hooked IOHIDUserDeviceHandleReport=%p", handleReport);
 	} else {
 		SCTLog(@"IOHIDUserDeviceHandleReport not found");
 	}
 }
*/
