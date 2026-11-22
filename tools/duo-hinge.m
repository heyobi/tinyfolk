// Vendored from https://github.com/tosbaha/duo-fold-control (tools/duo-hinge.m) at commit 6207cc897648959c3c2213ac3a2dcf38f6f9eb41.
// Reviewed 2026-11-20: no network, no file writes, no process launches; it only sends the hinge-angle HID message
// that Xcode's Device Hub sends to a booted iPhone Duo simulator. Used by scripts/sim-shots.sh for inner-display screenshots.
// Local change (Pleats, 2026-11-22): a "sweep" mode that moves the hinge smoothly over one connection, so the app can
// measure how often the system reports hinge angles while the hinge moves.
//
// MIT License
// 
// Copyright (c) 2026 Mustafa Dur
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// duo-hinge: set the hinge angle (fold state) of a booted iPhone Duo simulator.
//
// Runs on the Mac. It sends the same message DeviceHub's fold controls send:
//   host --XPC--> dtuhidd (inside the simulator, mach service
//   com.apple.coredevice.feature.remote.hid.vendordefined)
//   --> VendorDefined HID event (usagePage 0xFF61, usage 91) on the "avpCustom" service
//   --> locationd/CoreMotion hinge angle --> SpringBoard/UIKit fold state.
//
// Usage: duo-hinge [-d <udid>|booted] <closed|half|flat|0-180>
//        duo-hinge [-d <udid>|booted] sweep <from> <to> <seconds> [step-ms]   (smooth motion, default step 8 ms)
//   closed = 0°, half = 130° (DeviceHub's half-open preset), flat = 180°
//
// Build: clang -fobjc-arc -framework Foundation -o duo-hinge duo-hinge.m

#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>

#define SERVICE "com.apple.coredevice.feature.remote.hid.vendordefined"

// Private libxpc SPI used by CoreDevice's SimulatorCoreDevicePlugin to talk to simulator services.
extern xpc_endpoint_t xpc_endpoint_create_mach_port_4sim(mach_port_t port);
extern xpc_connection_t xpc_connection_create_from_endpoint(xpc_endpoint_t endpoint);
extern void xpc_connection_enable_sim2host_4sim(xpc_connection_t connection);

// --- Minimal OSSerializeBinary writer (IOKit binary property list) ---
enum {
    kEnd    = 0x80000000u,
    kDict   = 0x01000000u,
    kNumber = 0x04000000u,
    kSymbol = 0x08000000u,
    kString = 0x09000000u,
};

static void put32(NSMutableData *d, uint32_t v) { [d appendBytes:&v length:4]; }
static void putPadded(NSMutableData *d, const void *p, size_t n) {
    [d appendBytes:p length:n];
    static const uint8_t zero[4] = {0};
    if (d.length % 4) [d appendBytes:zero length:4 - d.length % 4];
}
static void putKey(NSMutableData *d, const char *k) {  // keys: NUL-terminated symbols
    size_t n = strlen(k) + 1; put32(d, kSymbol | (uint32_t)n); putPadded(d, k, n);
}
static void putString(NSMutableData *d, const char *s, BOOL last) {
    size_t n = strlen(s); put32(d, kString | (uint32_t)n | (last ? kEnd : 0)); putPadded(d, s, n);
}
static void putDouble(NSMutableData *d, double v, BOOL last) {  // same encoding DeviceHub uses
    put32(d, kNumber | 0x3f | (last ? kEnd : 0)); putPadded(d, &v, 8);
}

static NSData *hingePayload(double degrees) {
    NSMutableData *d = [NSMutableData data];
    put32(d, 0x000000d3);              // OSSerializeBinary signature
    put32(d, kDict | kEnd | 4);        // top-level dictionary with 4 entries
    putKey(d, "type");     putString(d, "range", NO);
    putKey(d, "value");    putDouble(d, degrees, NO);
    putKey(d, "source");   putString(d, "hinge-slider-control", NO);
    putKey(d, "provider"); putString(d, "com.apple.Virtualization.VirtualMachines", YES);
    return d;
}

static double parseAngle(NSString *a) {
    NSDictionary *named = @{ @"closed": @0, @"folded": @0, @"half": @130, @"halfopen": @130,
                             @"flat": @180, @"open": @180, @"unfolded": @180 };
    if (named[a.lowercaseString]) return [named[a.lowercaseString] doubleValue];
    NSScanner *s = [NSScanner scannerWithString:a]; double d;
    if ([s scanDouble:&d] && s.isAtEnd && d >= 0 && d <= 180) return d;
    fprintf(stderr, "invalid angle '%s' (use closed|half|flat or 0-180)\n", a.UTF8String); exit(2);
}

static id findDevice(NSString *udid) {
    NSString *developerDir = [[[NSProcessInfo processInfo] environment] objectForKey:@"DEVELOPER_DIR"]
        ?: @"/Applications/Xcode.app/Contents/Developer";
    if (!dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW)) {
        fprintf(stderr, "cannot load CoreSimulator: %s\n", dlerror()); exit(1);
    }
    NSError *err = nil;
    id ctx = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(NSClassFromString(@"SimServiceContext"),
        NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"), developerDir, &err);
    id set = ((id (*)(id, SEL, NSError **))objc_msgSend)(ctx, NSSelectorFromString(@"defaultDeviceSetWithError:"), &err);
    if (!set) { fprintf(stderr, "no device set: %s\n", err.description.UTF8String); exit(1); }

    for (id dev in [set valueForKey:@"devices"]) {
        NSString *devUDID = [[dev valueForKey:@"UDID"] UUIDString];
        BOOL booted = [[dev valueForKey:@"state"] unsignedLongLongValue] == 3; // SimDeviceStateBooted
        if ([udid isEqualToString:@"booted"] ? (booted && [[dev valueForKey:@"name"] containsString:@"Duo"])
                                             : [devUDID caseInsensitiveCompare:udid] == NSOrderedSame) {
            if (!booted) { fprintf(stderr, "device %s is not booted\n", devUDID.UTF8String); exit(1); }
            return dev;
        }
    }
    fprintf(stderr, "no matching device for '%s'\n", udid.UTF8String); exit(1);
}

static void sendAngle(xpc_connection_t conn, double angle) {
    NSData *data = hingePayload(angle);
    xpc_object_t payload = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(payload, "usagePage", 0xFF61);
    xpc_dictionary_set_uint64(payload, "usage", 91);
    xpc_dictionary_set_uint64(payload, "version", 0);
    xpc_dictionary_set_data(payload, "data", data.bytes, data.length);

    xpc_object_t msg = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(msg, "messageType", "IndigoVendorDefinedEvent");
    xpc_dictionary_set_string(msg, "featureIdentifier", SERVICE);
    xpc_dictionary_set_value(msg, "payload", payload);
    xpc_connection_send_message(conn, msg);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSString *udid = @"booted";
        NSMutableArray<NSString *> *rest = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            if ((!strcmp(argv[i], "-d") || !strcmp(argv[i], "--device")) && i + 1 < argc) udid = @(argv[++i]);
            else [rest addObject:@(argv[i])];
        }
        if (rest.count == 0) { fprintf(stderr, "usage: duo-hinge [-d <udid>|booted] <closed|half|flat|0-180> | sweep <from> <to> <seconds> [step-ms]\n"); return 2; }
        BOOL sweep = [rest[0] isEqualToString:@"sweep"];
        if (sweep && rest.count < 4) { fprintf(stderr, "usage: duo-hinge sweep <from> <to> <seconds> [step-ms]\n"); return 2; }
        double from = sweep ? parseAngle(rest[1]) : parseAngle(rest[0]);
        double to = sweep ? parseAngle(rest[2]) : from;
        double seconds = sweep ? [rest[3] doubleValue] : 0;
        double stepMs = (sweep && rest.count > 4) ? [rest[4] doubleValue] : 8;
        if (stepMs < 1) stepMs = 1;
        id device = findDevice(udid);

        NSError *err = nil;
        mach_port_t port = ((mach_port_t (*)(id, SEL, NSString *, NSError **))objc_msgSend)(
            device, NSSelectorFromString(@"lookup:error:"), @SERVICE, &err);
        if (port == MACH_PORT_NULL) { fprintf(stderr, "lookup of %s failed: %s\n", SERVICE, err.description.UTF8String); return 1; }

        xpc_connection_t conn = xpc_connection_create_from_endpoint(xpc_endpoint_create_mach_port_4sim(port));
        xpc_connection_enable_sim2host_4sim(conn);
        xpc_connection_set_event_handler(conn, ^(xpc_object_t e) {
            if (xpc_get_type(e) == XPC_TYPE_ERROR && e != XPC_ERROR_CONNECTION_INVALID)
                fprintf(stderr, "xpc error: %s\n", xpc_dictionary_get_string(e, XPC_ERROR_KEY_DESCRIPTION));
        });
        xpc_connection_resume(conn);

        if (sweep) {
            // Ease in and out like a hand would; one event every step-ms.
            int steps = (int)fmax(1, seconds * 1000.0 / stepMs);
            sendAngle(conn, from);
            usleep(300 * 1000);  // let locationd open the service before the motion starts
            for (int i = 1; i <= steps; i++) {
                double t = (double)i / steps;
                double e = 0.5 - 0.5 * cos(M_PI * t);
                sendAngle(conn, from + (to - from) * e);
                usleep((useconds_t)(stepMs * 1000));
            }
        } else {
            sendAngle(conn, from);
        }

        // Barrier: dtuhidd replies once everything sent before it has been dispatched.
        xpc_object_t barrier = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_bool(barrier, "isBarrier", true);
        xpc_object_t reply = xpc_connection_send_message_with_reply_sync(conn, barrier);
        if (xpc_get_type(reply) == XPC_TYPE_ERROR) {
            fprintf(stderr, "failed: %s\n", xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION));
            return 1;
        }
        // dtuhidd removes this connection's HID services when we disconnect; give
        // locationd a moment to open the service and pick up the queued event first.
        usleep(1000 * 1000);
        if (sweep) printf("hinge swept %g° → %g° in %gs\n", from, to, seconds);
        else printf("hinge set to %g°\n", from);
    }
    return 0;
}
