//
//  TSKSubworkflowTask.m
//  Task
//
//  Created by Prachi Gauriar on 12/27/2014.
//  Copyright (c) 2014 Two Toasters, LLC.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import <Task/TSKSubworkflowTask.h>

#import <Task/TaskErrors.h>
#import <Task/TSKWorkflow.h>


@implementation TSKSubworkflowTask

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name subworkflow:nil];
}


- (instancetype)initWithSubworkflow:(TSKWorkflow *)subworkflow
{
    return [self initWithName:nil subworkflow:subworkflow];
}


- (instancetype)initWithName:(NSString *)name subworkflow:(TSKWorkflow *)subworkflow
{
    NSParameterAssert(subworkflow);

    self = [super initWithName:name];
    if (self) {
        _subworkflow = subworkflow;

        [subworkflow.notificationCenter addObserver:self
                                           selector:@selector(subworkflowDidFinish:)
                                               name:TSKWorkflowDidFinishNotification
                                             object:subworkflow];
        [subworkflow.notificationCenter addObserver:self
                                           selector:@selector(subworkflowTaskDidFail:)
                                               name:TSKWorkflowTaskDidFailNotification
                                             object:subworkflow];

        [subworkflow addObserver:self
                      forKeyPath:@"allTasks"
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:@selector(allTasks)];
    }

    return self;
}


- (void)dealloc
{
    [self.subworkflow.notificationCenter removeObserver:self];
    [self.subworkflow removeObserver:self forKeyPath:@"allTasks" context:@selector(allTasks)];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != @selector(allTasks)) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // If the change kind is set, observe cancel notifications for the new tasks. This should only happen
    // the first time, but better safe than sorry
    NSKeyValueChange changeKind = [change[NSKeyValueChangeKindKey] unsignedIntegerValue];
    if (changeKind == NSKeyValueChangeSetting) {
        [self.subworkflow.notificationCenter removeObserver:self name:TSKTaskDidCancelNotification object:nil];
    }

    // Observe the new tasks
    for (TSKTask *task in change[NSKeyValueChangeNewKey]) {
        [self.subworkflow.notificationCenter addObserver:self selector:@selector(subworkflowTaskDidCancel:) name:TSKTaskDidCancelNotification object:task];
    }
}


#pragma mark -

- (void)main
{
    // If we don’t have any unfinished tasks, finish immediately
    if (![self.subworkflow hasUnfinishedTasks]) {
        [self finishWithResult:self.subworkflow];
        return;
    }

    // If we were cancelled while checking to see if we have unfinished tasks, return
    if (!self.isExecuting) {
        return;
    }

    // Get the earliest failed task
    __block NSDate *earliestFinishDate = [NSDate distantFuture];
    __block TSKTask *failedTask = nil;
    [self.subworkflow.allTasks enumerateObjectsUsingBlock:^(TSKTask *task, BOOL *stop) {
        if (task.isFailed && [task.finishDate compare:earliestFinishDate] < NSOrderedSame) {
            earliestFinishDate = task.finishDate;
            failedTask = task;
        }
    }];

    // If we were cancelled while getting the failed task set, return
    if (!self.isExecuting) {
        return;
    }

    if (failedTask) {
        [self failWithFailedSubworkflowTask:failedTask];
    } else {
        [self.subworkflow start];
    }
}


- (void)cancel
{
    [self.subworkflow cancel];
    [super cancel];
}


- (void)reset
{
    [self.subworkflow reset];
    [super reset];
}


- (void)retry
{
    [self.subworkflow retry];
    [super retry];
}


- (void)failWithFailedSubworkflowTask:(TSKTask *)task
{
    NSParameterAssert(task);
    [self failWithError:[NSError errorWithDomain:TSKTaskErrorDomain
                                            code:TSKErrorCodeSubworkflowTaskFailed
                                        userInfo:@{ TSKWorkflowFailedTaskKey : task }]];
}


#pragma mark - Subworkflow Task State

- (void)subworkflowDidFinish:(NSNotification *)notification
{
    [self finishWithResult:self.subworkflow];
}


- (void)subworkflowTaskDidFail:(NSNotification *)notification
{
    [self failWithFailedSubworkflowTask:notification.userInfo[TSKWorkflowFailedTaskKey]];
}


- (void)subworkflowTaskDidCancel:(NSNotification *)notification
{
    // We only want to put ourselves into the cancelled state, not cascade the cancel down to
    // our subworkflow. As such, invoke the superclass implementation, not our own
    [super cancel];
}

@end
