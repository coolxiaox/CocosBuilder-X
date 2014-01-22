/*
 * CocosBuilder: http://www.CocosBuilder.com
 *
 * Copyright (c) 2012 Zynga Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "ResourceManagerOutlineView.h"
#import "AppDelegate.h"
#import "ResourceManager.h"

@implementation ResourceManagerOutlineView

- (NSMenu*) menuForEvent:(NSEvent *)evt
{
    NSPoint pt = [self convertPoint:[evt locationInWindow] fromView:nil];
    int row=[self rowAtPoint:pt];
    
    id clickedItem = [self itemAtRow:row];

    NSMenu* menu = [AppDelegate appDelegate].menuContextResManager;
    menu.autoenablesItems = NO;
    
    NSArray* items = [menu itemArray];
    for (NSMenuItem* item in items)
    {
        if (item.action == @selector(menuCreateSmartSpriteSheet:))
        {
            if ([clickedItem isKindOfClass:[RMResource class]]) {
                RMResource* clickedResource = clickedItem;
                if (clickedResource.type == kCCBResTypeDirectory)
                {
                    RMDirectory* dir = clickedResource.data;

                    if (dir.isDynamicSpriteSheet)
                    {
                        item.title = @"删除智能精灵表";
                    }
                    else
                    {
                        item.title = @"创建智能精灵表";
                    }

                    [item setEnabled:YES];
                    item.tag = row;
                }
                else
                {
                    [item setEnabled:NO];
                }
            }
        }
        else if (item.action == @selector(menuEditSmartSpriteSheet:))
        {
            if ([clickedItem isKindOfClass:[RMResource class]]) {
                RMResource* clickedResource = clickedItem;
                [item setEnabled:NO];
                if (clickedResource.type == kCCBResTypeDirectory)
                {
                    RMDirectory* dir = clickedResource.data;
                    if (dir.isDynamicSpriteSheet)
                    {
                        [item setEnabled:YES];
                        item.tag = row;
                    }
                }
            }
        }
        else if (item.action == @selector(menuOpenExternal:))
        {
//            item.title = @"使用外部编辑器打开";
            item.title = @"在Finder中显示";

            if ([clickedItem isKindOfClass:[RMResource class]]) {
                RMResource* clickedResource = clickedItem;
                if (clickedResource.type == kCCBResTypeCCBFile)
                {
                    [item setEnabled:YES];
                    item.title = @"在Finder中显示";
                }
                else if (clickedResource.type == kCCBResTypeDirectory)
                {
                    [item setEnabled:YES];
                    item.title = @"在Finder中显示";
                }
                else
                {
                    [item setEnabled:YES];
                }
            }
            item.tag = row;
        }
        else if (item.action == @selector(menuReName:)){
            [item setEnabled:YES];
            item.tag = row;
        }
        else if (item.action == @selector(menuDuplicate:)){
            [item setEnabled:YES];
            item.tag = row;
        }
        else if (item.action == @selector(menuDelete:)){
            [item setEnabled:YES];
            item.tag = row;
        }
        else if (item.action == @selector(menuAddToGenList:)){
            item.tag = row;
            RMResource* clickedResource = clickedItem;
            if (clickedResource.type == kCCBResTypeCCBFile) {
                [item setEnabled:YES];
            }else{
                [item setEnabled:NO];
            }
        }
    }
    
    // TODO: Update menu
    
    return menu;
}

@end
