#include"../head.hpp"

//与join同步的变量
std::mutex synchronization_join_post;
ResultTuple * rstream_result_address;
ResultTuple * sstream_result_address;
unsigned long rstream_post_num = 0;
unsigned long sstream_post_num = 0;
bool post_r_valid = false;
bool post_s_valid = false;
int post_flag = 0;
int post_type = 0;
//提供给控制线程写的变量
bool ctrl_poster_exit = false;
bool ctrl_output_result_tuple = false;
bool ctrl_output_result_ts = true;
bool ctrl_output_result_delay = true;
bool ctrl_order_preserving = false;
unsigned long long report_delay_frequent = REPORT_DELAY_FREQUENT;
const long long SINK_BUCKETS = 100000;

void PostStatisticsThread(int threadid) {
//本地变量
std::random_device random_delay;
FileWriter result_writer(W_NAME,W_PUNC,true);
unsigned long long result_debug_report_count = 0;
unsigned long long result_debug_delay_sum = 0;
const unsigned long long vector_length = 1000000000;
vector<long long>vts(vector_length); 
vector<long long>vlatency(vector_length); 

const int log_blen = 13;
unsigned int blen = 1 << log_blen;
vector<unsigned int> num_v(SINK_BUCKETS);
//清空hash桶
for (size_t i = 0; i < SINK_BUCKETS; i++) num_v[i] = 0;
vector<ResultTuple> hash_v(SINK_BUCKETS << log_blen); 
long long id_mask = (1<<20) - 1;//低20位为流顺序id

unsigned long long index = 0;

long long initial_ts = get_ts();
long long ts_reminder = initial_ts;
long long start_output = initial_ts + 60000;
long long stop_output = initial_ts + window_length_in_ms + 120000;
while(1){
  //检查有无post指令
  bool post_code = false;
  ResultTuple * local_rstream_result_address;
  ResultTuple * local_sstream_result_address;
  unsigned long local_rstream_post_num = 0;
  unsigned long local_sstream_post_num = 0;
  bool local_post_r_valid = false;
  bool local_post_s_valid = false;
  if(!post_code){
    std::lock_guard<std::mutex> mtx_locker(synchronization_join_post); //访问同步区
    if(_post_ == post_type){
        local_rstream_result_address = rstream_result_address;
        local_sstream_result_address = sstream_result_address;
        local_rstream_post_num = rstream_post_num;
        local_sstream_post_num = sstream_post_num;
        local_post_r_valid = post_r_valid;
        local_post_s_valid = post_s_valid;
        post_type = _invalid_;
        post_code = true;        
    }    
  }
  //稍微延迟时间,避免过于频繁阻塞post线程
  if(!post_code) 
  {
    long unsigned int s = (random_delay() % 10000);
    long unsigned int tmp = 0;
    for (size_t i = 0; i < s; i++){ tmp = i; tmp = tmp * 1997;}
  }
  else{
  if(local_post_r_valid){
    local_post_r_valid = false;
    unsigned long long tuple_delay = 0;
    long long ts = 0;

    //cout << "local_post_r_valid, local_rstream_post_num = "<<local_rstream_post_num<<endl;
    if(local_rstream_post_num > 0){
        if(ctrl_order_preserving){ 
          unsigned long long tuple_id = 0;
          unsigned long long id_max = 0;
          //放置到hash桶
          for (size_t i = 0; i < local_rstream_post_num; i++)
          {
              ResultTuple rt = local_rstream_result_address[i];
              tuple_id = rt.stream_timestamp & id_mask;
              rt.stream_timestamp = rt.stream_timestamp >> 20;
              if(tuple_id > id_max) id_max = tuple_id;
              if(num_v[tuple_id] < blen){
                hash_v[(tuple_id << log_blen) + num_v[tuple_id]] = rt;
                num_v[tuple_id]++;  
              }          
          } 
          //cout << "local_rstream_post_num push to hash buckets" <<endl;
          //排序
          size_t pos = 0;
          for (size_t i = 0; i <= id_max; i++)
          {
              for (size_t j = 0; j < num_v[i]; j++)
              {
                  local_rstream_result_address[pos] = hash_v[(i << log_blen) + j];
                  pos++;
              } 
          }
          local_rstream_post_num = pos;
          //cout << "local_rstream_post_num read from hash buckets" <<endl;       
          //清空hash桶
          for (size_t i = 0; i <= id_max; i++) num_v[i] = 0;
          //cout << "local_rstream_post_num clear hash buckets" <<endl;
        }

        for (size_t i = 0; i < local_rstream_post_num; i++)
        {
            ResultTuple rt = local_rstream_result_address[i];
            // Line tl = ResultTuple_to_Line(rt);
            ts = get_ts();
            tuple_delay = ts - rt.stream_timestamp;
            // if(!ctrl_output_result_tuple) tl.values.clear();
            // if(ctrl_output_result_ts) tl.values.push_back(to_string(ts));//记录输出时间戳
            // if(ctrl_output_result_delay) tl.values.push_back(to_string(tuple_delay));//记录时延
            // if(ctrl_output_result_tuple || ctrl_output_result_ts || ctrl_output_result_delay)
            //result_writer.constructLineAndWrite(tl.values);

            if(ts > start_output){
              if(ts < stop_output){
                if(index < vector_length){
                  vts[index] = ts;
                  vlatency[index] = tuple_delay;
                  index++;                  
                }
              }
            }
            result_debug_delay_sum += tuple_delay;
            result_debug_report_count += 1;
            if((get_ts() - ts_reminder) > 1000){
              LOG << DEBUG << "Among ["<<result_debug_report_count<<"] results, avg_delay = ["
                <<(double)result_debug_delay_sum/result_debug_report_count<<"] ms." << std::endl;
              cout << "Among ["<<result_debug_report_count<<"] results, avg_delay = ["
                <<(double)result_debug_delay_sum/result_debug_report_count<<"] ms." << std::endl;
              ts_reminder = get_ts();
              result_debug_delay_sum = 0;
              result_debug_report_count = 0;
            }
        }               
    }
  }

  if(local_post_s_valid){
    local_post_s_valid = false;
    unsigned long long tuple_delay = 0;
    long long ts = 0;

    //cout << "local_post_s_valid, local_sstream_post_num = "<<local_sstream_post_num<<endl;
    if(local_sstream_post_num > 0){     
          if(ctrl_order_preserving){
          unsigned long long tuple_id = 0;
          unsigned long long  id_max = 0;
          //放置到hash桶
          for (size_t i = 0; i < local_sstream_post_num; i++)
          {
              ResultTuple rt = local_sstream_result_address[i];
              tuple_id = rt.stream_timestamp & id_mask;
              rt.stream_timestamp = rt.stream_timestamp >> 20;
              if(tuple_id > id_max) id_max = tuple_id;
              if(num_v[tuple_id] < blen){
                hash_v[(tuple_id << log_blen) + num_v[tuple_id]] = rt;
                num_v[tuple_id]++;
              }
          } 
          //cout << "local_sstream_post_num push to hash buckets" <<endl;
          //排序
          size_t pos = 0;
          for (size_t i = 0; i <= id_max; i++)
          {
              for (size_t j = 0; j < num_v[i]; j++)
              {
                  local_sstream_result_address[pos] = hash_v[(i << log_blen) + j];
                  pos++;
              } 
          } 
          local_sstream_post_num = pos;
          //cout << "local_sstream_post_num read from hash buckets" <<endl;      
          //清空hash桶
          for (size_t i = 0; i <= id_max; i++) num_v[i] = 0;
            //cout << "local_sstream_post_num clear hash buckets" <<endl;
        }

        for (size_t i = 0; i < local_sstream_post_num; i++)
        {
            ResultTuple rt = local_sstream_result_address[i];
            // Line tl = ResultTuple_to_Line(rt);
            ts = get_ts();
            tuple_delay = ts - rt.stream_timestamp;
            // if(!ctrl_output_result_tuple) tl.values.clear();
            // if(ctrl_output_result_ts) tl.values.push_back(to_string(ts));//记录输出时间戳
            // if(ctrl_output_result_delay) tl.values.push_back(to_string(tuple_delay));//记录时延
            // if(ctrl_output_result_tuple || ctrl_output_result_ts || ctrl_output_result_delay)
            //result_writer.constructLineAndWrite(tl.values);
            if(ts > start_output){
              if(ts < stop_output){
                if(index < vector_length){
                  vts[index] = ts;
                  vlatency[index] = tuple_delay;
                  index++;                  
                }
              }
            }
            result_debug_delay_sum += tuple_delay;
            result_debug_report_count += 1;
            if((get_ts() - ts_reminder) > 1000){
              LOG << DEBUG << "Among ["<<result_debug_report_count<<"] results, avg_delay = ["
                <<(double)result_debug_delay_sum/result_debug_report_count<<"] ms." << std::endl;
              cout << "Among ["<<result_debug_report_count<<"] results, avg_delay = ["
                <<(double)result_debug_delay_sum/result_debug_report_count<<"] ms." << std::endl;
              ts_reminder = get_ts();
              result_debug_delay_sum = 0;
              result_debug_report_count = 0;
            }
        }
    }
  }   
  
  std::lock_guard<std::mutex> mtx_locker(synchronization_join_post); //访问同步区,写入complete状态
  post_type = _complete_;
  post_code = false;        
 
  }// end of post_code

  //检查控制命令是否退出    
  if(ctrl_poster_exit) {
      LOG << DEBUG << "sink start write [" << index <<"] result to disk..." << std::endl;
      cout << "sink start write [" << index <<"] result to disk..." << std::endl;
      for(size_t i = 0; i < index; i++){
        vector<string> strs;
        strs.push_back(to_string(vts[i]));
        strs.push_back(to_string(vlatency[i]));
        result_writer.constructLineAndWrite(strs);
      }
      LOG << DEBUG << "write disk over, ctrl_poster_exit." << std::endl;
      break;
  }
}// end of while

}// end of thread
