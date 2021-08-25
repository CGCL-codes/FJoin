
#include"../head.hpp"

//提供给参数控制器写的变量
long source_speed = DEFAULT_SOURCE_SPEED;
long r_ratio = DEFAULT_R_RATIO;//r_ratio
long s_ratio = DEFAULT_S_RATIO;//s_ratio
//提供给控制线程读写的变量
bool ctrl_source_exit = false;
bool source_error_offline = false;
//本地变量
void SourceThread(int threadid) {
    LOG << DEBUG << "Source Online." << std::endl;
    //从文件产生流,打开rs流文件
    FileReader r_reader(R_DATA,R_PUNC);
    FileReader s_reader(S_DATA,S_PUNC);

    std::random_device rd;
    long long count_old = 0;
    long long count = 0;
    bool joiner_online = false;
    bool valid_last_emit_ts = false;
    long long last_emit_ts = 0;
    double emit_delta = 0;
    //long need_delay = 0;
    while(1) 
    {
        bool read_failed = false;
        //检查joiner线程是否在线
        joiner_online = joiner_online_status;
        if(joiner_online){
            //保存的上次发射时间戳有效，则依据时间差决定本次发射元组个数
            if(valid_last_emit_ts){
                size_t need_emit = 0;
                long long now_ts = get_ts();
                long get_source_speed = source_speed;
                double ms_per_tuple = (0>=get_source_speed)? 3600000 : (double)1000 / source_speed;
                double duration_time = (double)(now_ts - last_emit_ts) + emit_delta;
                while(duration_time >= ms_per_tuple){
                    ++need_emit;
                    duration_time -= ms_per_tuple;
                    if(duration_time < 0) duration_time = 0;
                }
                emit_delta = duration_time;
                count += need_emit;
                //根据RS发射比率决定产生随机数的范围
                long random_range = r_ratio + s_ratio;
                //循环发射元组
                for (size_t i = 0; i < need_emit; i++) {
                    //决定发射哪条流的元组
                    bool is_r = (rd() % random_range)>(s_ratio - 1);
                    Line t;
                    
                    if(is_r){
                        t.relation = R_NAME;
                        t.values = r_reader.readLineAndSplit();
                    }
                    else{
                        t.relation = S_NAME;
                        t.values = s_reader.readLineAndSplit();
                    }
                    t.is_r = is_r;
                    t.timestamp = get_ts();  
                    if(0 == t.values.size()) read_failed = true;   
                    if(!read_failed) tupleReadBuffer.push(t);
                }
                last_emit_ts = now_ts;
                valid_last_emit_ts = true;
            }
            else{
                //未记录上次时间戳，则保存本次有效时间戳，但不发射元组
                last_emit_ts = get_ts();
                valid_last_emit_ts = true;
                LOG << DEBUG << "Joiner online, valid_last_emit_ts set to [true].ts = ["<<last_emit_ts <<"]." << std::endl;                
            }

        }
        else{//joinner不在线
            if(valid_last_emit_ts)
                LOG << DEBUG << "Joiner offline, valid_last_emit_ts set to [false]." << std::endl;
            last_emit_ts = 0;
            valid_last_emit_ts = false;
            emit_delta = 0;
        }
        if(count - count_old > REPOT_SOURCE_LINES_FREQUENT) {
            LOG << DEBUG << "Source read lines = ["<< count <<"]." << std::endl;
            cout << "Source read lines = ["<< count <<"]." << std::endl;
            count_old = count;         
        }        
        //检查控制命令是否退出
        if(ctrl_source_exit) {
            LOG << DEBUG << "ctrl_source_exit, Source Offline." << std::endl;
            break;            
        }
        if(read_failed) {
            source_error_offline = true;
            LOG << DEBUG << "read tuple failed, Source Offline." << std::endl;
            break;            
        }
    }
}
