//
//  ANREye.swift
//  Pods
//
//  Created by zixun on 16/12/24.
//
//

import Foundation

//--------------------------------------------------------------------------
// MARK: - ANREyeDelegate
//--------------------------------------------------------------------------
@objc public protocol ANREyeDelegate: class {
    @objc optional func anrEye(anrEye:ANREye,
                               catchWithThreshold threshold:Double,
                               mainThreadBacktrace:String?,
                               allThreadBacktrace:String?)
    // 卡顿时长,startTime:开始时间,endTime:结束数据,都是以毫秒的时间戳
    @objc optional func anrEye(anrEye:ANREye,startTime:Int64,endTime: Int64,
                               catchWithThreshold threshold:Double,
                               mainThreadBacktrace:String?,
                               allThreadBacktrace:String?)
    // 卡顿时长,startTime:开始时间,endTime:结束数据,都是以毫秒的时间戳
    @objc optional func anrEye(anrEye:ANREye,startTime:Int64,endTime: Int64,
                               catchWithThreshold threshold:Double,
                               mainThreadBacktraceList:[[String:String]])
}
//--------------------------------------------------------------------------
// MARK: - ANREye
//--------------------------------------------------------------------------
 @objc open class ANREye: NSObject {
    
    //--------------------------------------------------------------------------
    // MARK: OPEN PROPERTY
    //--------------------------------------------------------------------------
   @objc open weak var delegate: ANREyeDelegate?
    
    open var isOpening: Bool {
        get {
            guard let pingThread = self.pingThread else {
                return false
            }
            return !pingThread.isCancelled
        }
    }
    //--------------------------------------------------------------------------
    // MARK: OPEN FUNCTION
    //--------------------------------------------------------------------------
    
    @objc open func open(with threshold:Double) {
        if Thread.current.isMainThread {
            //mach_thread_self() 获得线程内核端口的发送权限
            AppBacktrace.main_thread_id = mach_thread_self()
        }else {
            DispatchQueue.main.async {
                AppBacktrace.main_thread_id = mach_thread_self()
            }
        }
        
        self.pingThread = AppPingThread()
        //开始定时器记录
        self.startTimer(intervalTime: threshold / 2)
        self.pingThread?.startRecordingStackInformation(threshold: threshold,isCatonHandler: {[weak self] (isCaton) in
            if isCaton == false {//不卡顿
                self?.stackInformationArray.removeAll()
            }
            
            }, catonLengthhandler: {[weak self] (startTime, endTime) in
                guard let strongSelf = self else {
                    return
                }
                
                let statickList = strongSelf.stackInformationArray
                var stackLists: [[String: String]] = [[String: String]]()
                
                statickList.forEach({ (dict) in
                    stackLists.append(dict)
                })
                //print("-----卡---3"),将代理放在数组所在队列中,保证数据安全性
                strongSelf.stackInformationArray.safeQueue.async{
                    strongSelf.delegate?.anrEye?(anrEye: strongSelf, startTime: startTime, endTime: endTime, catchWithThreshold: threshold, mainThreadBacktraceList: stackLists)
                }
                strongSelf.stackInformationArray.removeAll()
        })
        
    }
    
   @objc open func close() {
        self.pingThread?.cancel()
        stopTimer()
    }
    //--------------------------------------------------------------------------
    // MARK: LIFE CYCLE
    //--------------------------------------------------------------------------
 
    
    //--------------------------------------------------------------------------
    // MARK: PRIVATE PROPERTY
    //--------------------------------------------------------------------------
    private var pingThread: AppPingThread?
    //记录堆栈信息
    private lazy var stackInformationArray:MSSafeArray<[String:String]> = {
         var stackArray: MSSafeArray<[String:String]> = MSSafeArray<[String:String]>() 
        return stackArray
    }()
    //定时器 定时器打印堆栈信息的
    private var timer: MSGCDTimer?
    private func startTimer(intervalTime: Double){
        if timer == nil {//定时器为nil,就创建定时器
            timer = MSGCDTimer(interval: .seconds(intervalTime), mode: .infinite, tolerance:.seconds(0), queue: nil, observer: { [weak self] (timer1) in
                self?.recordsStackInformation()
                
            })
            timer?.start()
        }else{//定时器不为nil,不用创建
           // timer?.reset(.seconds(intervalTime))
            timer?.start()
        }     
    }
    //暂停定时器
    private func pauseTimer(){
        self.timer?.pause();
    }
    //关闭定时器
    private func stopTimer(){
        DispatchQueue.main.async {
             self.timer?.pause();
             self.timer = nil;
        }
    }
    //记录堆栈信息
    private func recordsStackInformation() {
        let main = AppBacktrace.mainThread()
        let main1 = main.replacingOccurrences(of: "\n", with: "#&####")
        let startTime = self.currentTime()
        var stackDict:[String:String] = [String:String]()
        stackDict["startTime"] = startTime
        stackDict["stackInformation"] = main1
        self.stackInformationArray.append(stackDict)
       // print("--------1")
    }
    func currentTime() -> String {
        let time = NSDate().timeIntervalSince1970 * 1000
        let timeN = NSNumber(value: time).int64Value
        let stimeS = String.init(format: "%lld", timeN)
        return stimeS
    }
    
    deinit {
        print("ANREye--deinit")
    }
}

//--------------------------------------------------------------------------
// MARK: - GLOBAL DEFINE
//--------------------------------------------------------------------------
public typealias AppPingThreadCallBack = () -> Void
//卡顿时长回到
public typealias AppPingCatonLengthThreadCallBack = (Int64,Int64) -> Void
//是否卡顿
public typealias AppPingISCatonThreadCallBack = (Bool) -> Void

//--------------------------------------------------------------------------
// MARK: - AppPingThread
//--------------------------------------------------------------------------
private class AppPingThread: Thread {
    
    deinit {
        print("AppPingThread--deinit")
    }
    var isCatonMonitor: Bool?{
        didSet {
            if let isCatonMonitor1 = isCatonMonitor {
                if isCatonMonitor1 {
                    self.start()
                }else{
                    self.cancel()
                }
            }
            
        }
    }
    
    func start(threshold:Double, handler: @escaping AppPingThreadCallBack, catonLengthhandler:  @escaping AppPingCatonLengthThreadCallBack) {
        self.handler = handler
        self.threshold = threshold
        self.catonLengthhandler = catonLengthhandler
        self.start()
    }
    //开始记录堆栈信息,isCatonHandler是否卡顿 handler: @escaping AppPingThreadCallBack
    func startRecordingStackInformation(threshold:Double ,isCatonHandler: @escaping AppPingISCatonThreadCallBack, catonLengthhandler:  @escaping AppPingCatonLengthThreadCallBack) {
        self.threshold = threshold
        self.isCatonhandler = isCatonHandler
        self.catonLengthhandler = catonLengthhandler
        self.start()
    }
    //线程入口
    override func main() {
        
        while self.isCancelled == false {
            self.isMainThreadBlock = true
            //是否卡顿
            var isCaton: Bool = false
            let startTime = self.currentTime()
            DispatchQueue.main.async {
                self.isMainThreadBlock = false
                //发送信号量将semaphore的值+1，这个时候其他等待中的线程就会被唤醒执行（同等优先级下随机唤醒）
                self.semaphore.signal()
            }
            Thread.sleep(forTimeInterval:self.threshold )//
            if self.isMainThreadBlock  {
                isCaton = true
            }
            self.isCatonhandler?(isCaton)
            //DispatchTime.distantFuture， 等待信号量 timeout可以控制可等待的最长时间，设置为.distantFuture表示永久等待
            let _ = self.semaphore.wait(timeout: DispatchTime.distantFuture)
            //有卡顿信息才回调出去
            if isCaton {
                //如果是大于时间间隔就将时间回调出去
                let endTime = self.currentTime()
                 self.catonLengthhandler?(startTime,endTime)
            }
           
        }
    }
    //创建信号量 设置为0
    private let semaphore = DispatchSemaphore(value: 0)
    
    private var isMainThreadBlock = false
    
    private var threshold: Double = 0.4
    
    fileprivate var handler: (() -> Void)?
    //是否卡顿回调
    fileprivate var isCatonhandler: ((Bool) -> Void)?
    //卡顿时长block
    fileprivate var catonLengthhandler: ((Int64,Int64) -> Void)?
    
    func currentTime() -> Int64 {
        let time = NSDate().timeIntervalSince1970 * 1000
        let timeN = NSNumber(value: time).int64Value
        return timeN
    }
    
}
