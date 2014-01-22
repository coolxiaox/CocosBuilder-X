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

#import "SequencerHandler.h"
#import "AppDelegate.h"
#import "CCBGlobals.h"
#import "NodeInfo.h"
#import "CCNode+NodeInfo.h"
#import "PlugInNode.h"
#import "CCBWriterInternal.h"
#import "CCBReaderInternal.h"
#import "PositionPropertySetter.h"
#import "SequencerExpandBtnCell.h"
#import "SequencerStructureCell.h"
#import "SequencerCell.h"
#import "SequencerSequence.h"
#import "SequencerScrubberSelectionView.h"
#import "SequencerKeyframe.h"
#import "SequencerKeyframeEasing.h"
#import "SequencerNodeProperty.h"
#import "SequencerButtonCell.h"
#import "CCNode+NodeInfo.h"
#import "CCBDocument.h"
#import "CCBPCCBFile.h"
#import "SequencerCallbackChannel.h"
#import "SequencerSoundChannel.h"
#import <objc/runtime.h>
#import "NSPasteboard+CCB.h"

static SequencerHandler* sharedSequencerHandler;

@implementation SequencerHandler

@synthesize dragAndDropEnabled;
@synthesize currentSequence;
@synthesize scrubberSelectionView;
@synthesize timeDisplay;
@synthesize outlineHierarchy;
@synthesize timeScaleSlider;
@synthesize scroller;
@synthesize scrollView;
@synthesize contextKeyframe;
@synthesize loopPlayback;

#pragma mark Init and singleton object

- (id) initWithOutlineView:(NSOutlineView*)view
{
    self = [super init];
    if (!self) return NULL;
    
    sharedSequencerHandler = self;
    
    appDelegate = [AppDelegate appDelegate];
    outlineHierarchy = view;
    
    [outlineHierarchy setDataSource:self];
    [outlineHierarchy setDelegate:self];
    [outlineHierarchy reloadData];
    
    [outlineHierarchy registerForDraggedTypes:[NSArray arrayWithObjects: @"com.totollo.node", @"com.totollo.texture", @"com.totollo.template", @"com.totollo.ccb", @"com.totollo.PlugInNode",@"com.totollo.audio", NULL]];
    
    [[[outlineHierarchy outlineTableColumn] dataCell] setEditable:YES];
    
    return self;
}

+ (SequencerHandler*) sharedHandler
{
    return sharedSequencerHandler;
}

#pragma mark Handle Scale slider

- (void) setTimeScaleSlider:(NSSlider *)tss
{
    if (tss != timeScaleSlider)
    {
        [timeScaleSlider release];
        timeScaleSlider = [tss retain];
        
        [timeScaleSlider setTarget:self];
        [timeScaleSlider setAction:@selector(timeScaleSliderUpdated:)];
    }
}

- (void) timeScaleSliderUpdated:(id)sender
{
    currentSequence.timelineScale = timeScaleSlider.floatValue;
}

- (void) updateScaleSlider
{
    if (!currentSequence)
    {
        timeScaleSlider.doubleValue = kCCBDefaultTimelineScale;
        [timeScaleSlider setEnabled:NO];
        return;
    }
    
    [timeScaleSlider setEnabled:YES];
    
    
    timeScaleSlider.floatValue = currentSequence.timelineScale;
}

#pragma mark Handle scroller

- (float) visibleTimeArea
{
    NSTableColumn* column = [outlineHierarchy tableColumnWithIdentifier:@"sequencer"];
    return (column.width-2*TIMELINE_PAD_PIXELS)/currentSequence.timelineScale;
}

- (float) maxTimelineOffset
{
    float visibleTime = [self visibleTimeArea];
    return max(currentSequence.timelineLength - visibleTime, 0);
}

- (void) updateScroller
{
    float visibleTime = [self visibleTimeArea];
    float maxTimeScroll = currentSequence.timelineLength - visibleTime;
    
    float proportion = visibleTime/currentSequence.timelineLength;
    
    scroller.knobProportion = proportion;
    scroller.doubleValue = currentSequence.timelineOffset / maxTimeScroll;
    
    if (proportion < 1)
    {
        [scroller setEnabled:YES];
    }
    else
    {
        [scroller setEnabled:NO];
    }
}

- (void) updateScrollerToShowCurrentTime
{
    float visibleTime = [self visibleTimeArea];
    float maxTimeScroll = [self maxTimelineOffset];
    float timelinePosition = currentSequence.timelinePosition;
    if (maxTimeScroll > 0)
    {
        float minVisibleTime = scroller.doubleValue*(currentSequence.timelineLength-visibleTime);
        float maxVisibleTime = scroller.doubleValue*(currentSequence.timelineLength-visibleTime) + visibleTime;
        
        if (timelinePosition < minVisibleTime) {
            scroller.doubleValue = timelinePosition/(currentSequence.timelineLength-visibleTime);
            currentSequence.timelineOffset = scroller.doubleValue * (currentSequence.timelineLength - visibleTime);
        } else if (timelinePosition > maxVisibleTime) {
            scroller.doubleValue = (timelinePosition-visibleTime)/(currentSequence.timelineLength-visibleTime);
            currentSequence.timelineOffset = scroller.doubleValue * (currentSequence.timelineLength - visibleTime);
        }
    }
}

- (void) setScroller:(NSScroller *)s
{
    if (s != scroller)
    {
        [scroller release];
        scroller = [s retain];
        
        [scroller setTarget:self];
        [scroller setAction:@selector(scrollerUpdated:)];
        
        [self updateScroller];
    }
}

- (void) scrollerUpdated:(id)sender
{
    float newOffset = currentSequence.timelineOffset;
    float visibleTime = [self visibleTimeArea];
    
    switch ([scroller hitPart]) {
        case NSScrollerNoPart:
            break;
        case NSScrollerDecrementPage:
            newOffset -= 300 / currentSequence.timelineScale;
            break;
        case NSScrollerKnob:
            newOffset = scroller.doubleValue * (currentSequence.timelineLength - visibleTime);
            break;
        case NSScrollerIncrementPage:
            newOffset += 300 / currentSequence.timelineScale;
            break;
        case NSScrollerDecrementLine:
            newOffset -= 20 / currentSequence.timelineScale;
            break;
        case NSScrollerIncrementLine:
            newOffset += 20 / currentSequence.timelineScale;
            break;
        case NSScrollerKnobSlot:
            newOffset = scroller.doubleValue * (currentSequence.timelineLength - visibleTime);
            break;
        default:
            break;
    }
    
    
    currentSequence.timelineOffset = newOffset;
}

#pragma mark Outline view

- (void) updateOutlineViewSelection
{
    if (!appDelegate.selectedNodes.count)
    {
        [outlineHierarchy selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        return;
    }
    CCBGlobals* g = [CCBGlobals globals];
    
    // Expand parents of the selected node
    CCNode* node = [appDelegate.selectedNodes objectAtIndex:0];
    NSMutableArray* nodesToExpand = [NSMutableArray array];
    while (node != g.rootNode && node != NULL)
    {
        [nodesToExpand insertObject:node atIndex:0];
        node = node.parent;
    }
    for (int i = 0; i < [nodesToExpand count]; i++)
    {
        node = [nodesToExpand objectAtIndex:i];
        [outlineHierarchy expandItem:node.parent];
    }
    
    // Update the selection
    NSMutableIndexSet* indexes = [NSMutableIndexSet indexSet];
    
    for (CCNode* selectedNode in appDelegate.selectedNodes)
    {
        int row = (int)[outlineHierarchy rowForItem:selectedNode];
        [indexes addIndex:row];
    }
    [outlineHierarchy selectRowIndexes:indexes byExtendingSelection:NO];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    
    if ([[CCBGlobals globals] rootNode] == NULL) return 0;
    if (item == nil) return 3;
    
    CCNode* node = (CCNode*)item;
    CCArray* arr = [node children];
    
    return [arr count];
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if (item == nil) return YES;
    
    // Channels are not expandable
    if ([item isKindOfClass:[SequencerChannel class]])
    {
        return NO;
    }
    
    CCNode* node = (CCNode*)item;
    CCArray* arr = [node children];
    NodeInfo* info = node.userObject;
    PlugInNode* plugIn = info.plugIn;
    
    if ([arr count] == 0) return NO;
    if (!plugIn.canHaveChildren) return NO;
    
    return YES;
}


- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    CCBGlobals* g= [CCBGlobals globals];
    
    if (item == NULL)
    {
        if (index == 0)
        {
            // Callback channel
            return currentSequence.callbackChannel;
        }
        else if (index == 1)
        {
            // Sound channel
            return currentSequence.soundChannel;
        }
        else
        {
            // Nodes
            return g.rootNode;
        }
    }
    
    CCNode* node = (CCNode*)item;
    CCArray* arr = [node children];
    return [arr objectAtIndex:index];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    NSIndexSet* indexes = [outlineHierarchy selectedRowIndexes];
    NSMutableArray* selectedNodes = [NSMutableArray array];
    
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop){
        id item = [outlineHierarchy itemAtRow:idx];
        
        if ([item isKindOfClass:[SequencerChannel class]])
        {
            //
        }
        else
        {
            CCNode* node = item;
            [selectedNodes addObject:node];
        }
    }];
    
    appDelegate.selectedNodes = selectedNodes;
    
    [appDelegate updateInspectorFromSelection];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    CCNode* node = [[notification userInfo] objectForKey:@"NSObject"];
    [node setExtraProp:[NSNumber numberWithBool:NO] forKey:@"isExpanded"];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
    CCNode* node = [[notification userInfo] objectForKey:@"NSObject"];
    [node setExtraProp:[NSNumber numberWithBool:YES] forKey:@"isExpanded"];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    if (item == nil) return @"Root";
    
    
    CCNode* node = item;
    
    if ([item isKindOfClass:[SequencerChannel class]])
    {
        SequencerChannel* channel = item;
        return channel.displayName;
    }
    
    if ([tableColumn.identifier isEqualToString:@"sequencer"])
    {
        return @"";
    }
    
    if ([tableColumn.identifier isEqualToString:@"hidden"])
    {
//        NSLog(@"value %d",node.hidden);
        return @(node.hidden);
    }
    
    if ([tableColumn.identifier isEqualToString:@"locked"])
    {
        return @(node.locked);
    }
    
    return node.displayName;
}

-(void)setChildrenHidden:(bool)hidden withChildren:(CCArray*)children
{
    for(CCNode * child in children)
    {
        child.hidden = hidden;
        [self setChildrenHidden:hidden withChildren:child.children];
    }
}

// 变化的时候设置
- (void) outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    CCNode* node = item;
    
    if([tableColumn.identifier isEqualToString:@"hidden"])
    {
        bool hidden = [(NSNumber*)object boolValue];
        
//        node.hidden = hidden;
//        NSLog(@"set %d",node.hidden);
//        [outlineView reloadItem:node reloadChildren:YES];
    }
    else if([tableColumn.identifier isEqualToString:@"locked"])
    {
//        node.locked = [(NSNumber*)object boolValue];
    }
    else if (![object isEqualToString:node.displayName])
    {
        [[AppDelegate appDelegate] saveUndoStateWillChangeProperty:@"*nodeDisplayName"];
        node.displayName = object;
    }
}

//时间轴 眼睛 锁 展开
- (BOOL) outlineView:(NSOutlineView *)outline shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    NSLog(@"should edit?");
    if([tableColumn.identifier isEqualToString:@"hidden"])
    {
        return NO;
    }
    else if([tableColumn.identifier isEqualToString:@"locked"])
    {
        return NO;
    }
    else
    {
        [outline editColumn:0 row:[outline selectedRow] withEvent:[NSApp currentEvent] select:YES];
    }
    return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
    if (!dragAndDropEnabled) return NO;
    
    CCBGlobals* g = [CCBGlobals globals];
    
    NSMutableArray* pbNodes = [NSMutableArray array];
    for (id item in items) {
        if (![item isKindOfClass:[CCNode class]]) continue;
        
        CCNode* draggedNode = item;
        if (draggedNode == g.rootNode) continue;
        
        NSMutableDictionary* clipDict = [CCBWriterInternal dictionaryFromCCObject:draggedNode];
        
        [clipDict setObject:[NSNumber numberWithLongLong:(long long)draggedNode] forKey:@"srcNode"];
        [pbNodes addObject:clipDict];
    }
    
    if (pbNodes.count>0) {
        NSData* clipData = [NSKeyedArchiver archivedDataWithRootObject:pbNodes];
        [pboard declareTypes:[NSArray arrayWithObject:@"com.totollo.node"] owner:NULL];
        [pboard setData:clipData forType:@"com.totollo.node"];
        return YES;
    }
    
    return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id < NSDraggingInfo >)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    if (item == NULL)
        return NSDragOperationNone;
    
    
    CCBGlobals* g = [CCBGlobals globals];
    NSPasteboard* pb = [info draggingPasteboard];
    
    if ([item isKindOfClass:[CCNode class]])
    {
        NSData* nodeData = [pb dataForType:@"com.totollo.node"];
        if (nodeData)
        {
            NSDictionary* pbNodes = [NSKeyedUnarchiver unarchiveObjectWithData:nodeData];
            for (NSDictionary* clipDict in pbNodes) {
                CCNode* draggedNode = (CCNode*)[[clipDict objectForKey:@"srcNode"] longLongValue];
                
                CCNode* node = item;
                CCNode* parent = [node parent];
                while (parent && parent != g.rootNode)
                {
                    if (parent == draggedNode) return NSDragOperationNone;
                    parent = [parent parent];
                }
            }
            
            return NSDragOperationGeneric;
        }
        
    }
    
    // Dropped WavFile;
    NSArray* pbWavs = [pb propertyListsForType:@"com.totollo.wav"];
    
    if(pbWavs.count != 0)
    {
        if([item isKindOfClass:[SequencerSoundChannel class]])
        {
            // Dropped WavFile;
            for (NSDictionary* dict in pbWavs)
            {
                NSPoint mouseLocationInWindow = info.draggingLocation;
                NSPoint mouseLocation = [scrubberSelectionView  convertPoint: mouseLocationInWindow fromView: [appDelegate.window contentView]];
                
                currentSequence.soundChannel.dragAndDropTimeStamp = [currentSequence positionToTime:mouseLocation.x];
                
                currentSequence.soundChannel.needDragAndDropRedraw = YES;
                [scrubberSelectionView setNeedsDisplay:YES];
                
                return NSDragOperationGeneric;
            }
        }
        else
            return NSDragOperationNone;
    }
    
    if([item isKindOfClass:[SequencerSoundChannel class]] || [item isKindOfClass:[SequencerCallbackChannel class]] )
    {
        return NSDragOperationNone;//Restrict drag and drop
    }
    
    return NSDragOperationGeneric;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id < NSDraggingInfo >)info item:(id)item childIndex:(NSInteger)index
{
    NSPasteboard* pb = [info draggingPasteboard];
    
    NSData* clipData = [pb dataForType:@"com.totollo.node"];
    if (clipData)
    {
        NSArray* pbNodes = [NSKeyedUnarchiver unarchiveObjectWithData:clipData];
        for (NSDictionary*dict in [pbNodes reverseObjectEnumerator]) {
            CCNode* clipNode= [CCBReaderInternal nodeGraphFromDictionary:dict parentSize:CGSizeZero];
            if (![appDelegate addCCObject:clipNode toParent:item atIndex:index]) return NO;
            
            // Remove old node
            CCNode* draggedNode = (CCNode*)[[dict objectForKey:@"srcNode"] longLongValue];
            [appDelegate deleteNode:draggedNode];
            
            [appDelegate setSelectedNodes:[NSArray arrayWithObject: clipNode]];
            //[PositionPropertySetter refreshAllPositions];
        }
        return YES;
    }
    
    BOOL addedObject = NO;
    
    // Dropped textures
    clipData = [pb dataForType:@"com.totollo.texture"];
    if (clipData) {
        NSArray* pbTextures = [NSKeyedUnarchiver unarchiveObjectWithData:clipData];
        for (NSDictionary* dict in [pbTextures reverseObjectEnumerator])
        {
            [appDelegate dropAddSpriteNamed:[dict objectForKey:@"spriteFile"] inSpriteSheet:[dict objectForKey:@"spriteSheetFile"] at:ccp(0,0) parent:item index:index];
            //[PositionPropertySetter refreshAllPositions];
            addedObject = YES;
        }
    }
    
    // Dropped WavFile;
    clipData = [pb dataForType:@"com.totollo.wav"];
    if (clipData) {
        NSArray* pbWavs = [NSKeyedUnarchiver unarchiveObjectWithData:clipData];
        for (NSDictionary* dict in pbWavs)
        {
            NSPoint mouseLocationInWindow = info.draggingLocation;
            NSPoint mouseLocation = [scrubberSelectionView  convertPoint: mouseLocationInWindow fromView: [appDelegate.window contentView]];
            
            //Create Keyframe
            SequencerKeyframe * keyFrame = [currentSequence.soundChannel addDefaultKeyframeAtTime:[currentSequence positionToTime:mouseLocation.x]];
            NSMutableArray* newArr = [NSMutableArray arrayWithArray:keyFrame.value];
            [newArr replaceObjectAtIndex:kSoundChannelKeyFrameName withObject:dict[@"wavFile"]];
            keyFrame.value = newArr;
            
            addedObject = YES;
        }
    }
    
    // Dropped ccb-files
    clipData = [pb dataForType:@"com.totollo.ccb"];
    if (clipData) {
        NSArray* pbCCBs = [NSKeyedUnarchiver unarchiveObjectWithData:clipData];
        for (NSDictionary* dict in [pbCCBs reverseObjectEnumerator])
        {
            [appDelegate dropAddCCBFileNamed:[dict objectForKey:@"ccbFile"] at:ccp(0, 0) parent:item index:index];
            addedObject = YES;
        }
    }
    
    
//    // Dropped node plug-ins
//    NSArray* pbNodePlugIn = [pb propertyListsForType:@"com.totollo.PlugInNode"];
//    for (NSDictionary* dict in pbNodePlugIn)
//    {
//        [appDelegate dropAddPlugInNodeNamed:[dict objectForKey:@"nodeClassName"] parent:item index:index];
//        addedObject = YES;
//    }
    
    return addedObject;
}

- (BOOL) outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    if (![item isKindOfClass:[CCNode class]]) return NO;
    
    return YES;
}

- (CGFloat) outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
    if ([item isKindOfClass:[SequencerCallbackChannel class]])
    {
        return kCCBSeqDefaultRowHeight;
    }
    else if ([item isKindOfClass:[SequencerSoundChannel class]])
    {
        SequencerSoundChannel * channel = item;
        if(!channel.isEpanded)
            return kCCBSeqDefaultRowHeight;
        else
            return kCCBSeqAudioRowHeight;//+1;
    }
    
    CCNode* node = item;
    if (node.seqExpanded)
    {
        return kCCBSeqDefaultRowHeight * ([[node.plugIn animatablePropertiesForNode:node] count]);
    }
    else
    {
        return kCCBSeqDefaultRowHeight;
    }
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayOutlineCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	[cell setImagePosition:NSImageAbove];
}

- (void) outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    if ([item isKindOfClass:[SequencerChannel class]])
    {
        if ([tableColumn.identifier isEqualToString:@"expander"])
        {
            SequencerExpandBtnCell* expCell = cell;
            expCell.node = NULL;
            
            if ([item isKindOfClass:[SequencerCallbackChannel class]])
            {
                expCell.isExpanded = NO;
                expCell.canExpand = NO;
            }
            else if ([item isKindOfClass:[SequencerSoundChannel class]])
            {
                SequencerSoundChannel * soundChannel = item;
                
                expCell.isExpanded = soundChannel.isEpanded;
                expCell.canExpand = YES;
            }
        }
        else if ([tableColumn.identifier isEqualToString:@"structure"])
        {
            SequencerStructureCell* strCell = cell;
            strCell.node = NULL;
        }
        else if ([tableColumn.identifier isEqualToString:@"sequencer"])
        {
            SequencerCell* seqCell = cell;
            seqCell.node = NULL;
            
            if ([item isKindOfClass:[SequencerCallbackChannel class]])
            {
                seqCell.channel = (SequencerCallbackChannel*) item;
            }
            else if ([item isKindOfClass:[SequencerSoundChannel class]])
            {
                seqCell.channel = (SequencerSoundChannel*) item;
            }
        }
        else if([tableColumn.identifier isEqualToString:@"hidden"])
        {
            SequencerButtonCell * buttonCell = cell;
            buttonCell.node = nil;
            
            if ([item isKindOfClass:[SequencerCallbackChannel class]] ||
                [item isKindOfClass:[SequencerSoundChannel class]])
            {
                [buttonCell setTransparent:YES];
            }
            else
            {
                [buttonCell setTransparent:NO];
            }
            
            
        }else if ([tableColumn.identifier isEqualToString:@"locked"]){
            SequencerButtonCell * buttonCell = cell;
            buttonCell.node = nil;
            
            if ([item isKindOfClass:[SequencerCallbackChannel class]] ||
                [item isKindOfClass:[SequencerSoundChannel class]])
            {
                [buttonCell setTransparent:YES];
            }
            else
            {
                [buttonCell setTransparent:NO];
            }

        }
        return;
    }
    
    CCNode* node = item;
    
    BOOL isRootNode = (node == [CocosScene cocosScene].rootNode);
    int row = [outlineView rowForItem:item];
    
    if([tableColumn.identifier isEqualToString:@"hidden"])
    {
        SequencerButtonCell * buttonCell = cell;
        buttonCell.node = node;
        [buttonCell setTransparent:NO];
        buttonCell.tag = row;
        buttonCell.type = 0;
        [buttonCell setEnabled:!(node.hidden)];
//        [outlineHierarchy reloadData];
//        [node addObserver:self forKeyPath:@"hidden" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:NULL];
    }
    
    
    if([tableColumn.identifier isEqualToString:@"locked"])
    {
        SequencerButtonCell * buttonCell = cell;
        buttonCell.tag = row;
        [buttonCell setTransparent:NO];
        buttonCell.node = node;
        buttonCell.type =1;
        [buttonCell setEnabled:node.locked];
    }
    
    if ([tableColumn.identifier isEqualToString:@"expander"])
    {
        SequencerExpandBtnCell* expCell = cell;
        expCell.isExpanded = node.seqExpanded;
        expCell.canExpand = (!isRootNode);
        expCell.node = node;
    }
    else if ([tableColumn.identifier isEqualToString:@"structure"])
    {
        SequencerStructureCell* strCell = cell;
        strCell.node = node;
    }
    else if ([tableColumn.identifier isEqualToString:@"sequencer"])
    {
        SequencerCell* seqCell = cell;
        seqCell.node = node;
    }
}

//-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
//    [outlineHierarchy reloadData];
////    [self updateScroller];
//}

- (void) updateExpandedForNode:(CCNode*)node
{
    if ([self outlineView:outlineHierarchy isItemExpandable:node])
    {
        bool expanded = [[node extraPropForKey:@"isExpanded"] boolValue];
        if (expanded) [outlineHierarchy expandItem:node];
        else [outlineHierarchy collapseItem:node];
        
        CCArray* childs = [node children];
        for (int i = 0; i < [childs count]; i++)
        {
            CCNode* child = [childs objectAtIndex:i];
            [self updateExpandedForNode:child];
        }
    }
}

- (void) toggleSeqExpanderForRow:(int)row
{
    id item = [outlineHierarchy itemAtRow:row];
    
    if ([item isKindOfClass:[SequencerCallbackChannel class]])
    {
        return;
    }
    else if([item isKindOfClass:[SequencerSoundChannel class]])
    {
        SequencerSoundChannel * soundChannel = item;
        soundChannel.isEpanded = !soundChannel.isEpanded;
    }
    else
    {
        CCNode* node = item;
        
        if (node == [CocosScene cocosScene].rootNode && !node.seqExpanded)
            return;
        
        //if ([NSStringFromClass(node.class) isEqualToString:@"CCBPCCBFile"] && !node.seqExpanded) return;
        
        node.seqExpanded = !node.seqExpanded;
    }
    
    // Need to reload all data when changing heights of rows
    [outlineHierarchy reloadData];
}

-(void)toggleNodeHiddenForRow:(int)row{
    id item = [outlineHierarchy itemAtRow:row];
    if ([item isKindOfClass:[SequencerCallbackChannel class]] || [item isKindOfClass:[SequencerSoundChannel class]])
    {
        return;
    }
    CCNode* node = item;
    
    if (node == [CocosScene cocosScene].rootNode)
        return;
    node.hidden = !node.hidden;
//    NSLog(@"hidden is %d",node.hidden);
}

-(void)toggleNodeLockedForRow:(int)row{
    id item = [outlineHierarchy itemAtRow:row];
    if ([item isKindOfClass:[SequencerCallbackChannel class]] || [item isKindOfClass:[SequencerSoundChannel class]])
    {
        return;
    }
    CCNode* node = item;
    
    if (node == [CocosScene cocosScene].rootNode)
        return;
    node.locked = !node.locked;
//    NSLog(@"locked is %d",node.locked);
}


#pragma mark Timeline

- (void) redrawTimeline:(BOOL) reload
{
    [scrubberSelectionView setNeedsDisplay:YES];
    NSString* displayTime = [currentSequence currentDisplayTime];
    if (!displayTime) displayTime = @"00:00:00";
    [timeDisplay setStringValue:displayTime];
    [self updateScroller];
    if (reload) {
        [outlineHierarchy reloadData];
    }
}

- (void) redrawTimeline
{
    
    [self redrawTimeline:YES];
}

#pragma mark Util

- (void) deleteSequenceId:(int)seqId
{
    // Delete any keyframes for the sequence
    [[CocosScene cocosScene].rootNode deleteSequenceId:seqId];
    
    // Delete any chained sequence references
    for (SequencerSequence* seq in [AppDelegate appDelegate].currentDocument.sequences)
    {
        if (seq.chainedSequenceId == seqId)
        {
            seq.chainedSequenceId = -1;
        }
    }
    
    [[AppDelegate appDelegate] updateTimelineMenu];
}

- (void) deselectKeyframesForNode:(CCNode*)node
{
    [node deselectAllKeyframes];
    
    // Also deselect keyframes of children
    for (CCNode* child in node.children)
    {
        [self deselectKeyframesForNode:child];
    }
}

- (void) deselectAllKeyframes
{
    [self deselectKeyframesForNode:[[CocosScene cocosScene] rootNode]];
    [currentSequence.soundChannel.seqNodeProp deselectKeyframes];
    [currentSequence.callbackChannel.seqNodeProp deselectKeyframes];
    
    [outlineHierarchy reloadData];
}

- (BOOL) deleteSelectedKeyframesForCurrentSequence
{
    BOOL didDelete = [[CocosScene cocosScene].rootNode deleteSelectedKeyframesForSequenceId:currentSequence.sequenceId];
    
    didDelete |= [currentSequence.callbackChannel.seqNodeProp deleteSelectedKeyframes];
    didDelete |= [currentSequence.soundChannel.seqNodeProp deleteSelectedKeyframes];
    
    if (didDelete)
    {
        [self redrawTimeline];
        [self updatePropertiesToTimelinePosition];
        [[AppDelegate appDelegate] updateInspectorFromSelection];
    }
    return didDelete;
}

- (void) deleteDuplicateKeyframesForCurrentSequence
{
    BOOL didDelete = [[CocosScene cocosScene].rootNode deleteDuplicateKeyframesForSequenceId:currentSequence.sequenceId];
    
    if (didDelete)
    {
        [self redrawTimeline];
        [self updatePropertiesToTimelinePosition];
        [[AppDelegate appDelegate] updateInspectorFromSelection];
    }
}

- (void) deleteKeyframesForCurrentSequenceAfterTime:(float)time
{
    [[CocosScene cocosScene].rootNode deleteKeyframesAfterTime:time sequenceId:currentSequence.sequenceId];
}

- (void) addSelectedKeyframesForChannel:(SequencerChannel*) channel ToArray:(NSMutableArray*)keyframes
{
    for (SequencerKeyframe* keyframe in channel.seqNodeProp.keyframes)
    {
        if (keyframe.selected)
        {
            [keyframes addObject:keyframe];
        }
    }
}

- (void) addSelectedKeyframesForNode:(CCNode*)node toArray:(NSMutableArray*)keyframes
{
    [node addSelectedKeyframesToArray:keyframes];
    
    // Also add selected keyframes of children
    for (CCNode* child in node.children)
    {
        [self addSelectedKeyframesForNode:child toArray:keyframes];
    }
}

- (NSArray*) selectedKeyframesForCurrentSequence
{
    NSMutableArray* keyframes = [NSMutableArray array];
    [self addSelectedKeyframesForNode:[[CocosScene cocosScene] rootNode] toArray:keyframes];
    [self addSelectedKeyframesForChannel:currentSequence.callbackChannel ToArray:keyframes];
    [self addSelectedKeyframesForChannel:currentSequence.soundChannel ToArray:keyframes];
    return keyframes;
}

- (SequencerSequence*) seqId:(int)seqId inArray:(NSArray*)array
{
    for (SequencerSequence* seq in array)
    {
        if (seq.sequenceId == seqId) return seq;
    }
    return NULL;
}

- (void) updatePropertiesToTimelinePositionForNode:(CCNode*)node sequenceId:(int)seqId localTime:(float)time
{
    [node updatePropertiesTime:time sequenceId:seqId];
    
    if ([[node.plugIn animatablePropertiesForNode:node] containsObject:@"timeLine"]) {
        return;
    }
    
    // Also deselect keyframes of children
    for (CCNode* child in node.children)
    {
        int childSeqId = seqId;
        float localTime = time;
        
        // Sub ccb files uses different sequence id:s
        NSArray* childSequences = [child extraPropForKey:@"*sequences"];
        int childStartSequence = [[child extraPropForKey:@"*startSequence"] intValue];
        
        BOOL kfSeq = NO;
        
        if ([[child.plugIn animatablePropertiesForNode:child] containsObject:@"timeLine"]) {
            NSArray* sub_childSequences = [((CCBPCCBFile*)child).ccbFile extraPropForKey:@"*sequences"];
            NSArray* value = [child valueForProperty:@"timeLine" atTime:time sequenceId:seqId];
//            NSLog(@"%@   %@",value[0],value[1]);
            if (value.count==0) {
                continue;
            }
            if (![value[0] isEqualToString:@""]) {
                for (SequencerSequence* seq in sub_childSequences) {
                    if ([seq.name isEqualToString:value[0]]) {
                        if (localTime - [value[1] floatValue] > 0) {
                            [self updatePropertiesToTimelinePositionForNode:((CCBPCCBFile*)child).ccbFile sequenceId:seq.sequenceId localTime:localTime -[value[1] floatValue]];
                            kfSeq = YES;
                        }
                        break;
                    }
                }
            }
            if (!kfSeq) {
                [self updatePropertiesToTimelinePositionForNode:((CCBPCCBFile*)child).ccbFile sequenceId:[[((CCBPCCBFile*)child).ccbFile extraPropForKey:@"*startSequence"] intValue] localTime:localTime];
            }
        }
        
        
        if (childSequences && childStartSequence != -1)
        {
            childSeqId = childStartSequence;
            SequencerSequence* seq = [self seqId:childSeqId inArray:childSequences];
            
            while (localTime > seq.timelineLength && seq.chainedSequenceId != -1)
            {
                localTime -= seq.timelineLength;
                seq = [self seqId:seq.chainedSequenceId inArray:childSequences];
                childSeqId = seq.sequenceId;
            }
        }
        
        if (1) {
            [self updatePropertiesToTimelinePositionForNode:child sequenceId:childSeqId localTime:localTime];
        }
        
    }
}

- (void) updatePropertiesToTimelinePosition
{
    [self updatePropertiesToTimelinePositionForNode:[[CocosScene cocosScene] rootNode] sequenceId:currentSequence.sequenceId localTime:currentSequence.timelinePosition];
}

- (void) setCurrentSequence:(SequencerSequence *)seq
{
    if (seq != currentSequence)
    {
        [currentSequence release];
        currentSequence = [seq retain];
        
        [outlineHierarchy reloadData];
        [[AppDelegate appDelegate] updateTimelineMenu];
        [self redrawTimeline];
        [self updatePropertiesToTimelinePosition];
        [[AppDelegate appDelegate] updateInspectorFromSelection];
        [self updateScaleSlider];
    }
}

- (void) menuSetSequence:(id)sender
{
    int seqId = [sender tag];
    
    SequencerSequence* seqSet = NULL;
    for (SequencerSequence* seq in [AppDelegate appDelegate].currentDocument.sequences)
    {
        if (seq.sequenceId == seqId)
        {
            seqSet = seq;
            break;
        }
    }
    
    self.currentSequence = seqSet;
}

- (void) menuSetChainedSequence:(id)sender
{
    int seqId = [sender tag];
    if (seqId != self.currentSequence.chainedSequenceId)
    {
        [[AppDelegate appDelegate] saveUndoStateWillChangeProperty:@"*chainedseqid"];
        self.currentSequence.chainedSequenceId = [sender tag];
        [[AppDelegate appDelegate] updateTimelineMenu];
    }
}

#pragma mark Easings

- (void) setContextKeyframeEasingType:(int) type
{
    if (!contextKeyframe) return;
    if (contextKeyframe.easing.type == type) return;
    
    [[AppDelegate appDelegate] saveUndoStateWillChangeProperty:@"*keyframeeasing"];
    
    contextKeyframe.easing.type = type;
    [self redrawTimeline];
}

#pragma mark Adding keyframes

- (void) menuAddKeyframeNamed:(NSString*)prop
{
    CCNode* node = [AppDelegate appDelegate].selectedNode;
    if (!node) return;
    
    SequencerSequence* seq = self.currentSequence;
    
    [node addDefaultKeyframeForProperty:prop atTime: seq.timelinePosition sequenceId:seq.sequenceId];
    [self deleteDuplicateKeyframesForCurrentSequence];
    
    node.seqExpanded = YES;
}

- (BOOL) canInsertKeyframeNamed:(NSString*)prop
{
    CCNode* node = [AppDelegate appDelegate].selectedNode;
    if (!node) return NO;
    if (!prop) return NO;
    
    if ([node shouldDisableProperty:prop]) return NO;
    
    
    return [[node.plugIn animatablePropertiesForNode:node] containsObject:prop];
}

#pragma mark Destructor

- (void) dealloc
{
    self.currentSequence = NULL;
    self.scrubberSelectionView = NULL;
    self.timeDisplay = NULL;
    //self.sequences = NULL;
    
    [super dealloc];
}

@end
