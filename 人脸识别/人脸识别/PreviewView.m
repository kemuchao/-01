//
//  PreviewView.m
//  摄像机画面的捕捉和预览
//
//  Created by 柯木超 on 2019/9/3.
//  Copyright © 2019 柯木超. All rights reserved.
//
#define BOX_BOUNDS CGRectMake(0.0f, 0.0f, 150, 150.0f)
#import "PreviewView.h"
@interface PreviewView ()
@property (strong, nonatomic) UIView *focusBox;

@property(nonatomic,strong)CALayer *overlayLayer;

@property(strong,nonatomic)NSMutableDictionary *faceLayers;

@property(nonatomic,strong)AVCaptureVideoPreviewLayer *previewLayer;


@end
@implementation PreviewView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}


+(Class)layerClass {
    return [AVCaptureVideoPreviewLayer class];
}
- (AVCaptureSession*)session {
    //重写session方法，返回捕捉会话
    return [(AVCaptureVideoPreviewLayer*)self.layer session];
}
-(void)setSession:(AVCaptureSession *)session {
    //重写session属性的访问方法，在setSession:方法中访问视图layer属性。
    //AVCaptureVideoPreviewLayer 实例，并且设置AVCaptureSession 将捕捉数据直接输出到图层中，并确保与会话状态同步。
    [(AVCaptureVideoPreviewLayer*)self.layer setSession:session];
}

//关于UI的实现，例如手势，单击、双击 单击聚焦、双击曝光
- (void)setupView {
    self.faceLayers = [NSMutableDictionary dictionary];
    [(AVCaptureVideoPreviewLayer *)self.layer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    UITapGestureRecognizer *singleTapRecognizer =
    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    [self addGestureRecognizer:singleTapRecognizer];
    
     _focusBox = [self viewWithColor:[UIColor yellowColor]];
    [self addSubview:_focusBox];
    

    //初始化faceLayers属性  字典
    self.faceLayers = [NSMutableDictionary dictionary];
    
    //初始化overlayLayer
    self.overlayLayer = [CALayer layer];
    
    //设置它的frame
    self.overlayLayer.frame = self.bounds;
    
    //子图层形变 sublayerTransform属性   Core  Animation动画
    self.overlayLayer.sublayerTransform = CATransform3DMakePerspective(1000);
    
    //将子图层添加到预览图层来
    [self.layer addSublayer:self.overlayLayer];
    
}

// 人脸位置信息转换成屏幕坐标

- (UIView *)viewWithColor:(UIColor *)color {
    UIView *view = [[UIView alloc] initWithFrame:BOX_BOUNDS];
    view.backgroundColor = [UIColor clearColor];
    view.layer.borderColor = color.CGColor;
    view.layer.borderWidth = 5.0f;
    view.hidden = YES;
    return view;
}

- (void)runBoxAnimationOnView:(UIView *)view point:(CGPoint)point {
    view.center = point;
    view.hidden = NO;
    [UIView animateWithDuration:0.15f
                          delay:0.0f
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         view.layer.transform = CATransform3DMakeScale(0.5, 0.5, 1.0);
                     }
                     completion:^(BOOL complete) {
                         double delayInSeconds = 0.5f;
                         dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                         dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                             view.hidden = YES;
                             view.transform = CGAffineTransformIdentity;
                         });
                     }];
}


-(void)handleSingleTap:(UIGestureRecognizer *)recognizer {
    CGPoint point = [recognizer locationInView:self];
    [self runBoxAnimationOnView:self.focusBox
                          point:point];
    if(self.delegate){
        [self.delegate tappedToFocusAtPoint:point];
    }
}

// 将屏幕上点击的位置转化成摄像头的位置
-(CGPoint)captureDevicePointForPoint:(CGPoint)point{
    AVCaptureVideoPreviewLayer *layer = (AVCaptureVideoPreviewLayer *)self.layer;
    //将屏幕上点击的位置转化成摄像头的位置
    return [layer captureDevicePointOfInterestForPoint:point];
    
    //将摄像头的位置转化成屏幕上点击的位置
    // [layer pointForCaptureDevicePointOfInterest:point];
}



//将检测到的人脸进行可视化
-(void)showFace:(NSArray<__kindof AVMetadataFaceObject *> *)faces{
    
    //创建一个本地数组 保存转换后的人脸数据
    NSArray *transformedFaces = [self transformedFacesFromFaces:faces];
    
    //获取faceLayers的key，用于确定哪些人移除了视图并将对应的图层移出界面。
    /*
     支持同时识别10个人脸
     */
    NSMutableArray *lostFaces = [self.faceLayers.allKeys mutableCopy];
    
    //遍历每个转换的人脸对象
    for (AVMetadataFaceObject *face in transformedFaces) {
        
        //获取关联的faceID。这个属性唯一标识一个检测到的人脸
        NSNumber *faceID = @(face.faceID);
        
        //将对象从lostFaces 移除
        [lostFaces removeObject:faceID];
        
        //拿到当前faceID对应的layer
        CALayer *layer = self.faceLayers[faceID];
        
        //如果给定的faceID 没有找到对应的图层
        if (!layer) {
            
            //调用makeFaceLayer 创建一个新的人脸图层
            layer = [self makeFaceLayer];
            
            //将新的人脸图层添加到 overlayLayer上
            [self.overlayLayer addSublayer:layer];
            
            //将layer加入到字典中
            self.faceLayers[faceID] = layer;
            
        }
        
        //设置图层的transform属性 CATransform3DIdentity 图层默认变化 这样可以重新设置之前应用的变化
        layer.transform = CATransform3DIdentity;
        
        //图层的大小 = 人脸的大小
        layer.frame = face.bounds;
        
        //判断人脸对象是否具有有效的斜倾交。
        if (face.hasRollAngle) {
            
            //如果为YES,则获取相应的CATransform3D 值
            CATransform3D t = [self transformForRollAngle:face.rollAngle];
            
            //将它与标识变化关联在一起，并设置transform属性
            layer.transform = CATransform3DConcat(layer.transform, t);
        }
        
        
        //判断人脸对象是否具有有效的偏转角
        if (face.hasYawAngle) {
            
            //如果为YES,则获取相应的CATransform3D 值
            CATransform3D  t = [self transformForYawAngle:face.yawAngle];
            layer.transform = CATransform3DConcat(layer.transform, t);
            
        }
    }
    
    
    //遍历数组将剩下的人脸ID集合从上一个图层和faceLayers字典中移除
    for (NSNumber *faceID in lostFaces) {
        
        CALayer *layer = self.faceLayers[faceID];
        [layer removeFromSuperlayer];
        [self.faceLayers  removeObjectForKey:faceID];
    }
    
}


//将设备的坐标空间的人脸转换为视图空间的对象集合
- (NSArray *)transformedFacesFromFaces:(NSArray *)faces {
    
    NSMutableArray *transformeFaces = [NSMutableArray array];
    
    for (AVMetadataObject *face in faces) {
        
        //将摄像头的人脸数据 转换为 视图上的可展示的数据
        //简单说：UIKit的坐标 与 摄像头坐标系统（0，0）-（1，1）不一样。所以需要转换
        //转换需要考虑图层、镜像、视频重力、方向等因素 在iOS6.0之前需要开发者自己计算，但iOS6.0后提供方法
        AVMetadataObject *transformedFace = [self.previewLayer transformedMetadataObjectForMetadataObject:face];
        
        //转换成功后，加入到数组中
        [transformeFaces addObject:transformedFace];
        
        
    }
    
    return transformeFaces;
}

//获得layer
- (AVCaptureVideoPreviewLayer *)previewLayer {
    
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (CALayer *)makeFaceLayer {
    
    //创建一个layer
    CALayer *layer = [CALayer layer];
    
    //边框宽度为5.0f
    layer.borderWidth = 5.0f;
    
    //边框颜色为红色
    layer.borderColor = [UIColor redColor].CGColor;
    
    layer.contents = (id)[UIImage imageNamed:@"551.png"].CGImage;
    
    //返回layer
    return layer;
    
}



//将 RollAngle 的 rollAngleInDegrees 值转换为 CATransform3D
- (CATransform3D)transformForRollAngle:(CGFloat)rollAngleInDegrees {
    
    //将人脸对象得到的RollAngle 单位“度” 转为Core Animation需要的弧度值
    CGFloat rollAngleInRadians = THDegreesToRadians(rollAngleInDegrees);
    
    //将结果赋给CATransform3DMakeRotation x,y,z轴为0，0，1 得到绕Z轴倾斜角旋转转换
    return CATransform3DMakeRotation(rollAngleInRadians, 0.0f, 0.0f, 1.0f);
    
}


//将 YawAngle 的 yawAngleInDegrees 值转换为 CATransform3D
- (CATransform3D)transformForYawAngle:(CGFloat)yawAngleInDegrees {
    
    //将角度转换为弧度值
    CGFloat yawAngleInRaians = THDegreesToRadians(yawAngleInDegrees);
    
    //将结果CATransform3DMakeRotation x,y,z轴为0，-1，0 得到绕Y轴选择。
    //由于overlayer 需要应用sublayerTransform，所以图层会投射到z轴上，人脸从一侧转向另一侧会有3D 效果
    CATransform3D yawTransform = CATransform3DMakeRotation(yawAngleInRaians, 0.0f, -1.0f, 0.0f);
    
    //因为应用程序的界面固定为垂直方向，但需要为设备方向计算一个相应的旋转变换
    //如果不这样，会造成人脸图层的偏转效果不正确
    return CATransform3DConcat(yawTransform, [self orientationTransform]);
}

- (CATransform3D)orientationTransform {
    
    CGFloat angle = 0.0;
    //拿到设备方向
    switch ([UIDevice currentDevice].orientation) {
            
            //方向：下
        case UIDeviceOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
            
            //方向：右
        case UIDeviceOrientationLandscapeRight:
            angle = -M_PI / 2.0f;
            break;
            
            //方向：左
        case UIDeviceOrientationLandscapeLeft:
            angle = M_PI /2.0f;
            break;
            
            //其他
        default:
            angle = 0.0f;
            break;
    }
    
    return CATransform3DMakeRotation(angle, 0.0f, 0.0f, 1.0f);
    
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"


static CGFloat THDegreesToRadians(CGFloat degrees) {
    
    return degrees * M_PI / 180;
}


static CATransform3D CATransform3DMakePerspective(CGFloat eyePosition) {
    
    
    //CATransform3D 图层的旋转，缩放，偏移，歪斜和应用的透
    //CATransform3DIdentity是单位矩阵，该矩阵没有缩放，旋转，歪斜，透视。该矩阵应用到图层上，就是设置默认值。
    CATransform3D  transform = CATransform3DIdentity;
    
    
    //透视效果（就是近大远小），是通过设置m34 m34 = -1.0/D 默认是0.D越小透视效果越明显
    //D:eyePosition 观察者到投射面的距离
    transform.m34 = -1.0/eyePosition;
    
    return transform;
    
    
}


#pragma clang diagnostic pop

@end
