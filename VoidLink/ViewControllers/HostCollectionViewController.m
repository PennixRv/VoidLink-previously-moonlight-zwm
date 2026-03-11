//
//  HostCollectionViewController.m
//  VoidLink
//
//  Created by True砖家 on 2025/5/28.
//  Copyright 2025 True砖家 @ Bilibili. All rights reserved.
//

#import "HostCollectionViewController.h"
#import "HostCardView.h"
#import "TemporaryHost.h"
#import "VoidLink-Swift.h"

static const CGFloat cellOffsetY = 20;

@implementation HostCell {
    UIViewController* parentVC;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;
        self.layer.masksToBounds = NO;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.0;
        self.layer.shadowOffset = CGSizeZero;
        self.layer.shadowRadius = 0.0;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.cardView removeFromSuperview];
    self.cardView = nil;
}

- (CGFloat)getHostCardSizeFactor{
    TemporaryHost* dummyHost = [[TemporaryHost alloc] init];
    HostCardView* dummyCard = [[HostCardView alloc] initWithHost:dummyHost];
    return self.contentView.bounds.size.height/dummyCard.size.height;
}

- (UIViewController *)viewController {
    UIResponder *responder = self;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (void)assignDelegateForHostCard{
    parentVC = [self viewController].parentViewController;
    if(parentVC != nil){
        if([parentVC conformsToProtocol:@protocol(HostCardActionDelegate)]) self.cardView.delegate = (id<HostCardActionDelegate>) parentVC;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self assignDelegateForHostCard];
}

- (void)configureWithHost:(TemporaryHost *)host {
    if (!self.cardView) {
        self.cardView = [[HostCardView alloc] initWithHost:host andSizeFactor:[self getHostCardSizeFactor]];
        [self assignDelegateForHostCard];
        if(!self.cardView.superview){
            [self.contentView addSubview:self.cardView];
            [NSLayoutConstraint activateConstraints:@[
                [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
                [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0],
            ]];
        }
    }
}

@end

@interface HostCollectionViewController () <UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong, readwrite) NSMutableArray<TemporaryHost *> *items;
@property (nonatomic, strong) NSLayoutConstraint *collectionViewHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *superViewBottomConstraint;
@end

@implementation HostCollectionViewController{
    UICollectionViewFlowLayout *layout;
    CGFloat _horizontalPadding;
#if TARGET_OS_TV
    NSIndexPath* _lastFocusedIndexPath;
    UILongPressGestureRecognizer* _remoteSelectLongPressRecognizer;
#endif
}

- (instancetype)init {
    layout = [[UICollectionViewFlowLayout alloc] init];
    switch ([UIDevice currentDevice].userInterfaceIdiom) {
        case UIUserInterfaceIdiomPhone:
            _horizontalPadding = 5;
            break;
        case UIUserInterfaceIdiomPad:
        default:
            _horizontalPadding = 75;
            break;
    }
    layout.sectionInset = UIEdgeInsetsMake(7, _horizontalPadding, 0, _horizontalPadding); // 上、左、下、右的间距
    if (self = [super initWithCollectionViewLayout:layout]) {
        _interItemMinimumSpacing = 10;
        _minimumLineSpacing = 10;
        // _cellSize = CGSizeMake(100, 100);
        _items = [NSMutableArray array];

        _collectionViewHeightConstraint = [self.collectionView.heightAnchor constraintEqualToConstant:50];
        _collectionViewHeightConstraint.active = YES;
    }
    return self;
}

- (void)updateTheme {
    self.collectionView.backgroundColor = [ThemeManager hostViewBackgroundColor];
    for (HostCell *cell in [self.collectionView visibleCells]) {
        [cell.cardView updateTheme];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.collectionView registerClass:[HostCell class] forCellWithReuseIdentifier:@"HostCell"];
    self.collectionView.alwaysBounceVertical = NO;
    self.collectionView.showsVerticalScrollIndicator = NO;

#if TARGET_OS_TV
    self.collectionView.remembersLastFocusedIndexPath = YES;

    // tvOS: long-press Select to show host actions (Wake/Remove/etc).
    // We implement this at the collection view level to avoid relying on per-card gesture routing.
    _remoteSelectLongPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(remoteSelectLongPressed:)];
    _remoteSelectLongPressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    _remoteSelectLongPressRecognizer.minimumPressDuration = 0.6;
    _remoteSelectLongPressRecognizer.cancelsTouchesInView = YES;
    [self.collectionView addGestureRecognizer:_remoteSelectLongPressRecognizer];
#endif

    [self updateTheme];
}

#if TARGET_OS_TV
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath == nil || indexPath.item >= self.items.count) {
        return;
    }

    TemporaryHost *host = self.items[indexPath.item];
    UIViewController *parentVC = self.parentViewController;
    if ([parentVC conformsToProtocol:@protocol(HostCardActionDelegate)] &&
        [(id)parentVC respondsToSelector:@selector(appButtonTappedForHost:)]) {
        [(id<HostCardActionDelegate>)parentVC appButtonTappedForHost:host];
    }
}

- (void)remoteSelectLongPressed:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }

    NSIndexPath *ip = _lastFocusedIndexPath;
    if (ip == nil || ip.item >= self.items.count) {
        return;
    }

    TemporaryHost *host = self.items[ip.item];
    UIView *anchorView = [self.collectionView cellForItemAtIndexPath:ip] ?: self.collectionView;
    UIViewController *parentVC = self.parentViewController;
    if ([parentVC conformsToProtocol:@protocol(HostCardActionDelegate)] &&
        [(id)parentVC respondsToSelector:@selector(hostCardLongPressed:view:)]) {
        [(id<HostCardActionDelegate>)parentVC hostCardLongPressed:host view:anchorView];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didUpdateFocusInContext:(UICollectionViewFocusUpdateContext *)context withCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    _lastFocusedIndexPath = context.nextFocusedIndexPath;

    UICollectionViewCell *prevCell = context.previouslyFocusedIndexPath ? [collectionView cellForItemAtIndexPath:context.previouslyFocusedIndexPath] : nil;
    UICollectionViewCell *nextCell = context.nextFocusedIndexPath ? [collectionView cellForItemAtIndexPath:context.nextFocusedIndexPath] : nil;

    CGFloat scaleFactor = GenericUtils.liquidGlassEnabled ? 1.05 : 1.06;

    void (^applyUnfocused)(UICollectionViewCell *) = ^(UICollectionViewCell *cell) {
        if (!cell) return;
        cell.layer.zPosition = 0;
        cell.transform = CGAffineTransformIdentity;
        cell.layer.shadowOpacity = 0.0;
        cell.layer.shadowOffset = CGSizeZero;
        cell.layer.shadowRadius = 0.0;
    };

    void (^applyFocused)(UICollectionViewCell *) = ^(UICollectionViewCell *cell) {
        if (!cell) return;
        cell.clipsToBounds = NO;
        cell.contentView.clipsToBounds = NO;
        cell.layer.masksToBounds = NO;
        cell.layer.shadowColor = [UIColor blackColor].CGColor;

        CGAffineTransform t = CGAffineTransformMakeScale(scaleFactor, scaleFactor);
        CGFloat scaleDiff = (cell.bounds.size.height * scaleFactor - cell.bounds.size.height) / 2.0;
        t = CGAffineTransformTranslate(t, 0, -scaleDiff);

        cell.layer.zPosition = 100;
        cell.transform = t;
        cell.layer.shadowOffset = CGSizeMake(0, 18);
        cell.layer.shadowOpacity = GenericUtils.liquidGlassEnabled ? 0.14 : 0.20;
        cell.layer.shadowRadius = 22.0;
    };

    [coordinator addCoordinatedAnimations:^{
        applyUnfocused(prevCell);
        applyFocused(nextCell);
    } completion:nil];
}
#endif


#pragma mark - Data control

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSLog(@"View did appear");
}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
}

- (void)addHost:(TemporaryHost *)host {
    if(![self.items containsObject:host]){
        [self.items addObject:host];
        [self.collectionView reloadData];
    }
}

- (void)removeHost:(TemporaryHost *)host {
    if([self.items containsObject:host]){
        [self.items removeObject:host];
        [self.collectionView reloadData];
    }
}

- (void)removeLastItem {
    if (self.items.count > 0) {
        [self.items removeLastObject];
        [self.collectionView reloadData];
    }
}

- (NSInteger)numberOfRowsInCollectionView{
    NSInteger itemCount = [self.collectionView numberOfItemsInSection:0];
    
    if (itemCount == 0) return 0;
    
    NSMutableSet<NSNumber *> *rowYs = [NSMutableSet set];
    for (NSInteger i = 0; i < itemCount; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:0];
        UICollectionViewLayoutAttributes *attr = [layout layoutAttributesForItemAtIndexPath:indexPath];
        if (attr) {
            CGFloat y = CGRectGetMinY(attr.frame);
            [rowYs addObject:@(round(y))]; // round 防止浮点误差
        }
    }
    
    return rowYs.count;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat contentHeight = self.collectionView.collectionViewLayout.collectionViewContentSize.height;
    bool contentExceedsView = contentHeight > self.view.superview.bounds.size.height - self.view.frame.origin.y;
    if(contentExceedsView){
        if(!_superViewBottomConstraint){
            _superViewBottomConstraint = [self.view.bottomAnchor constraintEqualToAnchor:self.view.superview.safeAreaLayoutGuide.bottomAnchor constant:0];
            _superViewBottomConstraint.active = YES;
        }
    }
    else{
        _collectionViewHeightConstraint.constant = contentHeight;
    }
    
    if([self numberOfRowsInCollectionView] == 1) layout.sectionInset = UIEdgeInsetsMake(50, _horizontalPadding, 0, _horizontalPadding);
    else if([self numberOfRowsInCollectionView] == 2) layout.sectionInset = UIEdgeInsetsMake(17, _horizontalPadding, 0, _horizontalPadding);
    else layout.sectionInset = UIEdgeInsetsMake(10, _horizontalPadding, 0, _horizontalPadding);
    //if(contentExceedsView) layout.sectionInset = UIEdgeInsetsMake(7, _horizontalPadding, 0, _horizontalPadding);
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    HostCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HostCell" forIndexPath:indexPath];
    TemporaryHost *host = self.items[indexPath.item];
    [cell configureWithHost:host];
    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.cellSize;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return self.interItemMinimumSpacing;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return self.minimumLineSpacing;
}

@end
