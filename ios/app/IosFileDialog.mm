#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cstddef>
#include <string>
#include <vector>

extern "C" void banjopad_complete_ios_file_dialog(bool success, const char *path);
extern "C" void banjopad_complete_ios_file_dialog_multiple(
    bool success,
    const char *const *paths,
    size_t path_count);

@class BanjoPadDocumentPickerDelegate;

namespace {
enum class PickerMode {
    Rom,
    Mods,
};

static BanjoPadDocumentPickerDelegate *picker_delegate = nil;

UIViewController *presenting_view_controller() {
    UIWindow *window = nil;

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }

        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }

        if (window == nil) {
            window = ((UIWindowScene *)scene).windows.firstObject;
        }
        if (window != nil) {
            break;
        }
    }

    if (window == nil) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                if (window != nil) {
                    break;
                }
            }
        }
    }

    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    return controller;
}

NSURL *copy_security_scoped_url(NSURL *source_url, PickerMode mode) {
    const BOOL accessed = [source_url startAccessingSecurityScopedResource];

    NSString *folder_name = mode == PickerMode::Rom ? @"rom-import" : @"mod-import";
    NSURL *folder_url = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:folder_name
        isDirectory:YES];

    NSError *directory_error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:folder_url
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&directory_error]) {
        if (accessed) {
            [source_url stopAccessingSecurityScopedResource];
        }
        NSLog(@"BANJOPAD_IOS picker temp directory failed: %@", directory_error);
        return nil;
    }

    NSString *filename = source_url.lastPathComponent;
    if (filename.length == 0) {
        filename = @"import.bin";
    }
    NSString *unique_filename = [NSString stringWithFormat:@"%@-%@",
        NSUUID.UUID.UUIDString, filename];
    NSURL *destination_url = [folder_url URLByAppendingPathComponent:unique_filename];

    __block BOOL copied = NO;
    __block NSError *copy_error = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:source_url
                                    options:0
                                      error:&copy_error
                                 byAccessor:^(NSURL *coordinated_url) {
        copied = [NSFileManager.defaultManager copyItemAtURL:coordinated_url
                                                      toURL:destination_url
                                                      error:&copy_error];
    }];

    if (accessed) {
        [source_url stopAccessingSecurityScopedResource];
    }

    if (!copied) {
        NSLog(@"BANJOPAD_IOS picker copy failed: %@", copy_error);
        return nil;
    }

    return destination_url;
}

void complete_picker(PickerMode mode, NSArray<NSURL *> *selected_urls) {
    NSMutableArray<NSURL *> *copied_urls = [NSMutableArray arrayWithCapacity:selected_urls.count];
    for (NSURL *selected_url in selected_urls) {
        NSURL *copied_url = copy_security_scoped_url(selected_url, mode);
        if (copied_url != nil) {
            [copied_urls addObject:copied_url];
        }
    }

    picker_delegate = nil;

    if (mode == PickerMode::Rom) {
        NSURL *rom_url = copied_urls.firstObject;
        banjopad_complete_ios_file_dialog(
            rom_url != nil,
            rom_url != nil ? rom_url.fileSystemRepresentation : nullptr);
        if (rom_url != nil) {
            [NSFileManager.defaultManager removeItemAtURL:rom_url error:nil];
        }
        return;
    }

    std::vector<std::string> path_storage;
    path_storage.reserve(copied_urls.count);
    for (NSURL *url in copied_urls) {
        path_storage.emplace_back(url.fileSystemRepresentation);
    }

    std::vector<const char *> paths;
    paths.reserve(path_storage.size());
    for (const std::string &path : path_storage) {
        paths.push_back(path.c_str());
    }

    banjopad_complete_ios_file_dialog_multiple(
        !paths.empty(),
        paths.empty() ? nullptr : paths.data(),
        paths.size());

    for (NSURL *url in copied_urls) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
}
} // namespace

@interface BanjoPadDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, assign) PickerMode mode;
@end

@implementation BanjoPadDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    complete_picker(self.mode, urls);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    complete_picker(self.mode, @[]);
}
@end

extern "C" void banjopad_present_ios_file_dialog(bool multiple) {
    dispatch_async(dispatch_get_main_queue(), ^{
        const PickerMode mode = multiple ? PickerMode::Mods : PickerMode::Rom;
        UIViewController *presenter = presenting_view_controller();
        if (presenter == nil || picker_delegate != nil) {
            complete_picker(mode, @[]);
            return;
        }

        NSMutableArray<UTType *> *content_types = [NSMutableArray arrayWithObject:UTTypeData];
        for (NSString *extension in @[@"z64", @"v64", @"n64", @"rtz", @"nrm"]) {
            UTType *type = [UTType typeWithFilenameExtension:extension
                                           conformingToType:UTTypeData];
            if (type != nil) {
                [content_types addObject:type];
            }
        }

        picker_delegate = [[BanjoPadDocumentPickerDelegate alloc] init];
        picker_delegate.mode = mode;

        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:content_types
                                                                       asCopy:NO];
        picker.delegate = picker_delegate;
        picker.allowsMultipleSelection = multiple;

        UIPopoverPresentationController *popover = picker.popoverPresentationController;
        if (popover != nil) {
            popover.sourceView = presenter.view;
            popover.sourceRect = CGRectMake(
                CGRectGetMidX(presenter.view.bounds),
                CGRectGetMidY(presenter.view.bounds),
                1.0,
                1.0);
            popover.permittedArrowDirections = 0;
        }

        [presenter presentViewController:picker animated:YES completion:nil];
    });
}
