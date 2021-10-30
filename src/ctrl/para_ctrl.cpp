
#include"../head.hpp"

string R_NAME;
string R_DATA;
string S_NAME;
string S_DATA;
string W_NAME;
//设定的默认参数
string R_PUNC;
string S_PUNC;
string W_PUNC;

void ParaCtrlThread(int threadid) {
    //读取配置文件进行初始化配置
    //cout<<"input config source:"<<endl;
    string cfg_filename = "run.cfg";
    //cin >> cfg_filename;
    ifstream cfg(cfg_filename.c_str());
    if(!cfg.good()){
        initial_run_join = 2;
        return;
    }
    string temp;
    unsigned int default_source_speed = DEFAULT_SOURCE_SPEED;
    unsigned int max_source_speed = MAX_SUSTAINABLE_THROUPUT;
    long long test_time_in_ms = 0;
    long long read_fifo_count_old = 0;
    long long add_speed_step = 0;
    long long avg_speed = 0;
    long long loop_count = 0;
    bool add_speed_test = false;
    bool add_speed_test_over = false;
    while(1)
    {
        getline(cfg,temp);
        if (cfg.eof()) break; // 文件结束判断
        if(string::npos !=temp.find("end")) {break;}

        unsigned int start = temp.find(":")+1;
        if(string::npos !=temp.find("R_NAME")) {R_NAME = temp.substr(start,temp.size()- start - 1);}
        if(string::npos !=temp.find("R_DATA")) {R_DATA = temp.substr(start,temp.size()- start - 1);}
        if(string::npos !=temp.find("S_NAME")) {S_NAME = temp.substr(start,temp.size()- start - 1);}
        if(string::npos !=temp.find("S_DATA")) {S_DATA = temp.substr(start,temp.size()- start - 1);}
        if(string::npos !=temp.find("W_NAME")) {W_NAME = temp.substr(start,temp.size()- start - 1);}

        if(string::npos !=temp.find("R_PUNC")) {R_PUNC = temp.substr(start,temp.size()- start - 1);}
        if(string::npos !=temp.find("S_PUNC")) {S_PUNC = temp.substr(start,temp.size()- start - 1);}
        if(string::npos !=temp.find("W_PUNC")) {W_PUNC = temp.substr(start,temp.size()- start - 1);}

        if(string::npos !=temp.find("window_length_in_ms"))  {window_length_in_ms = stoi(temp.substr(start));}
        if(string::npos !=temp.find("max_join_delay_in_ms")) {max_join_delay_in_ms = stoi(temp.substr(start));}
        if(string::npos !=temp.find("test_time_in_ms"))      {test_time_in_ms = stoi(temp.substr(start));}
        if(string::npos !=temp.find("add_speed_step"))       {add_speed_step = stoi(temp.substr(start));}

        if(string::npos !=temp.find("default_source_speed")) {default_source_speed = stoi(temp.substr(start));}
        if(string::npos !=temp.find("max_source_speed"))     {max_source_speed = stoi(temp.substr(start));}
        if(string::npos !=temp.find("r_ratio"))              {r_ratio = stoi(temp.substr(start));}
        if(string::npos !=temp.find("s_ratio"))              {s_ratio = stoi(temp.substr(start));}
        if(string::npos !=temp.find("order_preserving"))     {ctrl_order_preserving = true;}
        if(string::npos !=temp.find("post_result_tuple"))    {ctrl_output_result_tuple = true;}
        if(string::npos !=temp.find("post_result_ts"))       {ctrl_output_result_ts = true;}
        if(string::npos !=temp.find("post_result_delay"))    {ctrl_output_result_delay = true;}
        if(string::npos !=temp.find("add_speed_test"))       {add_speed_test = true;}
    }

        LOG << DEBUG 
        << "\n  R_NAME = ["<< R_NAME <<"] " 
        << "\n  R_DATA = ["<< R_DATA <<"] "
        << "\n  S_NAME = ["<< S_NAME <<"] "
        << "\n  S_DATA = ["<< S_DATA <<"] "
        << "\n  W_NAME = ["<< W_NAME <<"] "
        << "\n  R_PUNC = ["<< R_PUNC <<"] "
        << "\n  S_PUNC = ["<< S_PUNC <<"] "
        << "\n  W_PUNC = ["<< W_PUNC <<"] "
        << "\n  window_length_in_ms  = ["<< window_length_in_ms <<"] "
        << "\n  max_join_delay_in_ms = ["<< max_join_delay_in_ms <<"] "
        << "\n  test_time_in_ms      = ["<< test_time_in_ms <<"] "
        << "\n  default_source_speed = ["<< default_source_speed <<"] "
        << "\n  max_source_speed     = ["<< max_source_speed <<"] "
        << "\n  r_ratio              = ["<< r_ratio <<"] "
        << "\n  s_ratio              = ["<< s_ratio <<"] "
        << "\n  add_speed_step       = ["<< add_speed_step <<"] "
        << "\n  order_preserving     = ["<< ctrl_order_preserving <<"] "
        << "\n  add_speed_test       = ["<< add_speed_test <<"] "
        << "\n  post_result_tuple    = ["<< ctrl_output_result_tuple <<"] "
        << "\n  post_result_ts       = ["<< ctrl_output_result_ts <<"] "
        << "\n  post_result_delay    = ["<< ctrl_order_preserving <<"] "<< std::endl;


    long long initial =  get_ts();
    long long start =  initial;
    long long now =  initial;
    bool speed_up = false;
    bool speed_down = false;
    std::random_device rd_speed;
    LOG << DEBUG <<"para_ctrl init completed."<<std::endl;
    initial_run_join = 1; //通知main初始化完成启动所有线程
    //控制流速进行测试   
    while(1){
        now = get_ts();
        //测试完成则退出
        if((now - initial > test_time_in_ms) || source_error_offline || add_speed_test_over){
        	loop_count = loop_count == 0 ? 1: loop_count;
            avg_speed = avg_speed / loop_count;
            LOG << DEBUG << "avg_speed = ["<<avg_speed <<"]." << std::endl;
            if(source_error_offline)
                LOG << DEBUG << "source_error_offline, test exit." << std::endl;
            if(now - initial > test_time_in_ms)
                LOG << DEBUG << "reach test_time_in_ms, test completed and exit." << std::endl;
             if(add_speed_test_over)
                LOG << DEBUG << "speed unsustainable, add_speed_test completed and exit." << std::endl;
            ctrl_source_exit = true;
            ctrl_joiner_exit = true;
            ctrl_poster_exit = true;
            break;
        }
        //设置流速
        if(now - start >= 1000){//每一秒修改一次流速
            // cout<<"test : window : total "
            //     <<now-initial<<" : "<<window_length_in_ms<<" : "<<test_time_in_ms<<" ms "<<endl;
            long source_speed_next = source_speed;
            long buffer_size = tupleReadBuffer.size();
            cout <<"                                                buffersize:" << buffer_size<<endl;
            if(buffer_size < ((max_join_delay_in_ms>>1) * 20000) >> 10){
                speed_up = true;  speed_down = false;
            }
            else if(buffer_size > ((max_join_delay_in_ms << 1) * 20000) >> 10){
                speed_up = false;  speed_down = true;
            }
            if(!add_speed_test){//正常测时延和最大吞吐
                if((now - initial) <= (window_length_in_ms + 1000))//处于开始运行的第一个窗口期内
                {
                    if(speed_down){
                        source_speed_next = source_speed_next * 0.98 - 1;//减少2%
                        if(source_speed_next < 0) source_speed_next = 0;
                    }
                    else if(speed_up){
                        source_speed_next = (source_speed_next > default_source_speed >> 1 )?
                            (source_speed_next * 1.02 + 1) : (default_source_speed + 1);//增加2%
                        if(source_speed_next > default_source_speed) source_speed_next = default_source_speed;//设置上限为默认流速
                    }
                    else{
                        ;//保持原值不变
                    }
                }
                else if((now - initial) <= window_length_in_ms + 300000)//处于开始运行的第二个窗口期内
                    source_speed_next = source_speed;
                else{//第二个窗口期之后
                    if(speed_down){
                        source_speed_next = source_speed_next * 0.99 - 1;//减少1%
                        if(source_speed_next < 0) source_speed_next = 0;
                    }
                    else if(speed_up){
                        source_speed_next = source_speed_next * 1.01 + 1;//增加1%
                        if(source_speed_next > max_source_speed) source_speed_next = max_source_speed;//设置上限为最大流速                 
                    }
                    else{
                        ;//保持合适的值不变
                    }
                    if((now - initial) >= (window_length_in_ms + 120000)){//统计一个平均时延
                        avg_speed += source_speed_next;
                        loop_count ++;
                        LOG << DEBUG << "avg_speed = ["<<avg_speed/loop_count <<"]." << std::endl;
                    }
                }
            }


            else{//测增加流速
                if((now - initial) <= (window_length_in_ms + 1000))//处于开始运行的第一个窗口期内
                {
                    if(speed_down){
                        source_speed_next = source_speed_next * 0.98 - 1;//减少2%
                        if(source_speed_next < 0) source_speed_next = 0;
                    }
                    else if(speed_up){
                        source_speed_next = (source_speed_next > default_source_speed >> 1 )?
                            (source_speed_next * 1.02 + 1) : ((default_source_speed >> 1) + 1);//增加2%
                        if(source_speed_next > default_source_speed) source_speed_next = default_source_speed;//设置上限为默认流速
                    }
                    else{
                        ;//保持原值不变
                    }
                }
                else if((now - initial) <= window_length_in_ms + 10000)//10s过渡期
                    source_speed_next = default_source_speed;
                else{//开始加流速
                    if(buffer_size > 500000){ //堆积了50万数据
                        add_speed_test_over = true;
                    }
                    else{ //不断增加流速
                        source_speed_next = source_speed_next + add_speed_step;          
                    }
                }
            }

            LOG << DEBUG <<"source_speed will set to ["<<source_speed_next <<"]."<< std::endl;

            long long read_fifo_count_new = read_fifo_count;
            LOG << DEBUG <<"In [" << now - start << "] ms, join process tuples num = ["<<read_fifo_count_new - read_fifo_count_old <<"]."<< std::endl;

            cout <<"source_speed will set to ["<<source_speed_next <<"]."<< std::endl;
            read_fifo_count_old = read_fifo_count_new;

            source_speed = source_speed_next;
            start = now;            
        }
    }
    return;
}
