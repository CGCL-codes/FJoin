#include"../head.hpp"

using std::default_random_engine;
using std::generate;
using std::uniform_int_distribution;
using std::vector;

//source写的元组队列
threadsafe_queue<Line> tupleReadBuffer;
//提供给source读的状态
bool joiner_online_status = false;
long long read_fifo_count = 0;
//提供给控制器写的变量
bool ctrl_joiner_exit = false;
unsigned int window_length_in_ms = DEFAULT_WIN_LEN_IN_MS;//window_length_in_ms
unsigned int max_join_delay_in_ms = DEFAULT_MAX_DELAY_IN_MS; //max_join_delay_in_ms

//本地变量
std::random_device random_delay;


int rotate (int flag){
    return (0 == flag)? 1 : 0;
}

unsigned int  cgtz (unsigned int n){//check_greater_than_zero
    return (0 == n)? 1 : n;
}

#ifdef USE_FPGA
// An event callback function that prints the operations performed by the OpenCL
// runtime.
void event_cb(cl_event event1, cl_int cmd_status, void *data) {
  cl_int err;
  cl_command_type command;
  cl::Event event(event1, true);
  OCL_CHECK(err, err = event.getInfo(CL_EVENT_COMMAND_TYPE, &command));
  cl_int status;
  OCL_CHECK(err,
            err = event.getInfo(CL_EVENT_COMMAND_EXECUTION_STATUS, &status));
  const char *command_str;
  const char *status_str;
  switch (command) {
  case CL_COMMAND_READ_BUFFER:
    command_str = "buffer read";
    break;
  case CL_COMMAND_WRITE_BUFFER:
    command_str = "buffer write";
    break;
  case CL_COMMAND_NDRANGE_KERNEL:
    command_str = "kernel";
    break;
  case CL_COMMAND_MAP_BUFFER:
    command_str = "kernel";
    break;
  case CL_COMMAND_COPY_BUFFER:
    command_str = "kernel";
    break;
  case CL_COMMAND_MIGRATE_MEM_OBJECTS:
    command_str = "buffer migrate";
    break;
  default:
    command_str = "unknown";
  }
  switch (status) {
  case CL_QUEUED:
    status_str = "Queued";
    break;
  case CL_SUBMITTED:
    status_str = "Submitted";
    break;
  case CL_RUNNING:
    status_str = "Executing";
    break;
  case CL_COMPLETE:
    status_str = "Completed";
    break;
  }
  printf("[%s]: %s %s\n", reinterpret_cast<char *>(data), status_str,
         command_str);
  fflush(stdout);
}

// Sets the callback for a particular event
void set_callback(cl::Event event, const char *queue_name) {
  cl_int err;
  OCL_CHECK(err, err = event.setCallback(CL_COMPLETE, event_cb, (void *)queue_name));
}

uint64_t get_duration_ns(const cl::Event &event) {
  uint64_t nstimestart, nstimeend;
  cl_int err;
  OCL_CHECK(err, err = event.getProfilingInfo<uint64_t>(
                     CL_PROFILING_COMMAND_START, &nstimestart));
  OCL_CHECK(err, err = event.getProfilingInfo<uint64_t>(
                     CL_PROFILING_COMMAND_END, &nstimeend));
  return (nstimeend - nstimestart);
}
#endif
/************************************************************************************************************************
*************************************************************************************************************************
*********************************************    THREAD START    ********************************************************
*************************************************************************************************************************
*************************************************************************************************************************/

void JoinThread(const char * binaryFile, int threadid) {
#ifdef USE_FPGA
//识别并访问加速卡设备
cl_int err;
cl::CommandQueue qr;
cl::CommandQueue qs;
cl::Context context;
cl::Kernel krnl_r_stream_join;
cl::Kernel krnl_s_stream_join;
std::cout << "Creating Context..." << std::endl;
auto devices = xcl::get_xil_devices();
auto fileBuf = xcl::read_binary_file(binaryFile);
cl::Program::Binaries bins{{fileBuf.data(), fileBuf.size()}};
int valid_device = 0;
for (unsigned int i = 0; i < devices.size(); i++) {
    auto device = devices[i];
    OCL_CHECK(err, context = cl::Context(device, NULL, NULL, NULL, &err));
    OCL_CHECK(err, qr = cl::CommandQueue(context, device,
                                        CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE,
                                        &err));
    OCL_CHECK(err, qs = cl::CommandQueue(context, device,
                                        CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE,
                                        &err));
    std::cout << "Trying to program device[" << i
              << "]: " << device.getInfo<CL_DEVICE_NAME>() << std::endl;
    cl::Program program(context, {device}, bins, NULL, &err);
    if (err != CL_SUCCESS) {
      std::cout << "Failed to program device[" << i << "] with xclbin file!\n";
    } else {
      std::cout << "Device[" << i << "]: program successful!\n";
      OCL_CHECK(err, krnl_r_stream_join = cl::Kernel(program, "stream_r_join", &err));
      OCL_CHECK(err, krnl_s_stream_join = cl::Kernel(program, "stream_s_join", &err));
      valid_device++;
      break; // we break because we found a valid device
    }
}
if (valid_device == 0) {
    std::cout << "Failed to program any device found, exit!\n";
    exit(EXIT_FAILURE);
}
#endif

//窗口缓冲区
vector<RTuple, aligned_allocator<RTuple>> rWindow(R_WINDOW_BUFFER_SIZE); 
vector<STuple, aligned_allocator<STuple>> sWindow(S_WINDOW_BUFFER_SIZE); 
//创建固定缓冲区info[4]、result[4]
// Aligning memory in 4K boundary
vector<ResultTuple, aligned_allocator<ResultTuple>> rStreamResultArray0(RESULT_BUFFER_SIZE); 
vector<ResultTuple, aligned_allocator<ResultTuple>> rStreamResultArray1(RESULT_BUFFER_SIZE); 
vector<ResultTuple, aligned_allocator<ResultTuple>> sStreamResultArray0(RESULT_BUFFER_SIZE); 
vector<ResultTuple, aligned_allocator<ResultTuple>> sStreamResultArray1(RESULT_BUFFER_SIZE); 
vector<InfoTuple,   aligned_allocator<InfoTuple>>   rStreamInfoArray0(INFO_BUFFER_SIZE);  
vector<InfoTuple,   aligned_allocator<InfoTuple>>   rStreamInfoArray1(INFO_BUFFER_SIZE); 
vector<InfoTuple,   aligned_allocator<InfoTuple>>   sStreamInfoArray0(INFO_BUFFER_SIZE);  
vector<InfoTuple,   aligned_allocator<InfoTuple>>   sStreamInfoArray1(INFO_BUFFER_SIZE); 

vector<ResultTuple, aligned_allocator<ResultTuple>> *pResultArray[2][2];
vector<InfoTuple,   aligned_allocator<InfoTuple>>   *pInfoArray[2][2];

pResultArray[0][_r_] = &rStreamResultArray0;
pResultArray[1][_r_] = &rStreamResultArray1;
pResultArray[0][_s_] = &sStreamResultArray0;
pResultArray[1][_s_] = &sStreamResultArray1;
pInfoArray[0][_r_] = &rStreamInfoArray0;
pInfoArray[1][_r_] = &rStreamInfoArray1;
pInfoArray[0][_s_] = &sStreamInfoArray0;
pInfoArray[1][_s_] = &sStreamInfoArray1;

// Clear the info
for (size_t i = 0; i < INTS_PER_TUPLE; i++)
{
    rStreamInfoArray0[0].data[i] = 0;
    rStreamInfoArray1[0].data[i] = 0;
    sStreamInfoArray0[0].data[i] = 0;
    sStreamInfoArray1[0].data[i] = 0;
}

//工作状态变量
unsigned int rWindowStart = 0;
unsigned int rWindowEnd = 0;
unsigned int sWindowStart = 0;
unsigned int sWindowEnd = 0;
unsigned int rStreamVernier = 0;
unsigned int sStreamVernier = 0;

int flag = 0;
bool result_reading[2][2]={false};
bool stream_computing[2][2]={false};
bool result_posting[2][2]={false};
bool move_host_r_window = false;
bool move_host_s_window = false;

#ifdef USE_FPGA
//调度事件变量
cl::Event kernel_events[2][2];
cl::Event read_info_events[2][2];
cl::Event read_result_events[2][2];
cl::Event migrate_stream_event[2][2];
cl::Event migrate_window_event[2][2];
vector<cl::Event> wait_migrate_list_r;
vector<cl::Event> wait_calculate_list_r;
vector<cl::Event> wait_migrate_list_s;
vector<cl::Event> wait_calculate_list_s;  
//cl_buffer变量
cl::Buffer buffer_r_stream_result[2];
cl::Buffer buffer_r_stream[2];
cl::Buffer buffer_r_stream_info[2];
cl::Buffer buffer_s_stream_result[2];
cl::Buffer buffer_s_stream[2];
cl::Buffer buffer_s_stream_info[2];

//cl_mem_ext_ptr_t 变量
cl_mem_ext_ptr_t buffer_r_stream_result_mem_ptr[2];
cl_mem_ext_ptr_t buffer_r_stream_mem_ptr[2];
cl_mem_ext_ptr_t buffer_r_stream_info_mem_ptr[2];
cl_mem_ext_ptr_t buffer_s_stream_result_mem_ptr[2];
cl_mem_ext_ptr_t buffer_s_stream_mem_ptr[2];
cl_mem_ext_ptr_t buffer_s_stream_info_mem_ptr[2];

cl::Buffer       buffer_r_window; 
cl_mem_ext_ptr_t buffer_r_window_mem_ptr;
cl::Buffer       buffer_s_window; 
cl_mem_ext_ptr_t buffer_s_window_mem_ptr;

buffer_r_window_mem_ptr.flags = 33 | XCL_MEM_TOPOLOGY;
buffer_r_window_mem_ptr.obj = NULL;
buffer_r_window_mem_ptr.param = 0;
OCL_CHECK(err, buffer_r_window = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_ONLY |  CL_MEM_EXT_PTR_XILINX),
                R_WINDOW_BUFFER_SIZE * BYTES_PER_TUPLE, &buffer_r_window_mem_ptr, &err));
buffer_s_window_mem_ptr.flags = 32 | XCL_MEM_TOPOLOGY;
buffer_s_window_mem_ptr.obj = NULL;
buffer_s_window_mem_ptr.param = 0;
OCL_CHECK(err, buffer_s_window = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_ONLY |  CL_MEM_EXT_PTR_XILINX),
                S_WINDOW_BUFFER_SIZE * BYTES_PER_TUPLE, &buffer_s_window_mem_ptr, &err));

for (size_t i = 0; i < 2; ++i)
{
  buffer_r_stream_result_mem_ptr[i].flags = 32 | XCL_MEM_TOPOLOGY;
  buffer_r_stream_result_mem_ptr[i].obj = &(*pResultArray[i][_r_])[0];
  buffer_r_stream_result_mem_ptr[i].param = 0;
  //cout << "create buffer size ="<<(unsigned int)RESULT_BUFFER_SIZE * BYTES_PER_TUPLE <<endl;
  OCL_CHECK(err, buffer_r_stream_result[i] = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR | CL_MEM_EXT_PTR_XILINX),
      (unsigned int)RESULT_BUFFER_SIZE * BYTES_PER_TUPLE, &buffer_r_stream_result_mem_ptr[i], &err));

  buffer_r_stream_info_mem_ptr[i].flags = 32 | XCL_MEM_TOPOLOGY;
  buffer_r_stream_info_mem_ptr[i].obj = &(*pInfoArray[i][_r_])[0];
  buffer_r_stream_info_mem_ptr[i].param = 0;

  OCL_CHECK(err, buffer_r_stream_info[i] = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR | CL_MEM_EXT_PTR_XILINX),
      (unsigned int)INFO_BUFFER_SIZE * BYTES_PER_TUPLE, &buffer_r_stream_info_mem_ptr[i], &err));

  buffer_r_stream_mem_ptr[i].flags = 32 | XCL_MEM_TOPOLOGY;
  buffer_r_stream_mem_ptr[i].obj = NULL;
  buffer_r_stream_mem_ptr[i].param = 0;
  OCL_CHECK(err, buffer_r_stream[i] = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_ONLY |  CL_MEM_EXT_PTR_XILINX),
                  MAX_STREAM_SIZE * BYTES_PER_TUPLE, &buffer_r_stream_mem_ptr[i], &err));

  buffer_s_stream_result_mem_ptr[i].flags = 33 | XCL_MEM_TOPOLOGY;
  buffer_s_stream_result_mem_ptr[i].obj = &(*pResultArray[i][_s_])[0];
  buffer_s_stream_result_mem_ptr[i].param = 0;
  OCL_CHECK(err, buffer_s_stream_result[i] = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR | CL_MEM_EXT_PTR_XILINX),
      (unsigned int)RESULT_BUFFER_SIZE * BYTES_PER_TUPLE, &buffer_s_stream_result_mem_ptr[i], &err));

  buffer_s_stream_info_mem_ptr[i].flags = 33 | XCL_MEM_TOPOLOGY;
  buffer_s_stream_info_mem_ptr[i].obj = &(*pInfoArray[i][_s_])[0];
  buffer_s_stream_info_mem_ptr[i].param = 0;
  OCL_CHECK(err, buffer_s_stream_info[i] = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR | CL_MEM_EXT_PTR_XILINX),
      (unsigned int)INFO_BUFFER_SIZE * BYTES_PER_TUPLE, &buffer_s_stream_info_mem_ptr[i], &err));

  buffer_s_stream_mem_ptr[i].flags = 33 | XCL_MEM_TOPOLOGY;
  buffer_s_stream_mem_ptr[i].obj = NULL;  
  buffer_s_stream_mem_ptr[i].param = 0;
  OCL_CHECK(err, buffer_s_stream[i] = cl::Buffer(context, (cl_mem_flags)(CL_MEM_READ_ONLY |  CL_MEM_EXT_PTR_XILINX),
                  MAX_STREAM_SIZE * BYTES_PER_TUPLE, &buffer_s_stream_mem_ptr[i], &err));

}

#endif


long long initial_ts = get_ts();
long long ts_reminder = initial_ts;
long long loop_start_ts = initial_ts;
long long last_read_queue_ts = initial_ts;
unsigned long long loop_num = 0;

joiner_online_status = true;
/************************************************************************************************************************
*************************************************************************************************************************
**********************************************    LOOP START    *********************************************************
*************************************************************************************************************************
*************************************************************************************************************************/
while(1){
loop_start_ts = get_ts();  
int rflag = rotate(flag); 

//准备内核参数
unsigned int rWindowStartAlign = rWindowStart & (~63);//后6位置为0,以对齐4KB
unsigned int sWindowStartAlign = sWindowStart & (~63);//后6位置为0,以对齐4KB
unsigned int rStreamVernierAlign = rStreamVernier & (~63);//后6位置为0,以对齐4KB
unsigned int sStreamVernierAlign = sStreamVernier & (~63);//后6位置为0,以对齐4KB
unsigned int rAlign = rWindowStart - rWindowStartAlign;
unsigned int sAlign = sWindowStart - sWindowStartAlign;
unsigned int r_stream_length = rWindowEnd - rStreamVernier;
unsigned int s_stream_length = sWindowEnd - sStreamVernier;
unsigned int r_window_length = rWindowEnd - rWindowStart + rAlign;
unsigned int s_window_length = sWindowEnd - sWindowStart + sAlign;
unsigned int r_window_migrate_length = rWindowEnd - rStreamVernierAlign;
unsigned int s_window_migrate_length = sWindowEnd - sStreamVernierAlign;
unsigned int r_stream_result_max = RESULT_BUFFER_SIZE;  
unsigned int s_stream_result_max = RESULT_BUFFER_SIZE;  
unsigned int window_in_ms = window_length_in_ms;
            #ifdef RUN_SIMULATION  
                LOG << DEBUG << "Prepare args..."
                << "\n  r_stream_length   = ["<< r_stream_length <<"] " 
                << "\n  s_stream_length   = ["<< s_stream_length <<"] "
                << "\n  r_window_length   = ["<< r_window_length <<"] "
                << "\n  s_window_length   = ["<< s_window_length <<"] "
                << "\n  rWindowStartAlign = ["<< rWindowStartAlign <<"] "
                << "\n  sWindowStartAlign = ["<< sWindowStartAlign <<"] "
                << "\n  rStreamVernier    = ["<< rStreamVernier <<"] "
                << "\n  sStreamVernier    = ["<< sStreamVernier <<"] "<< std::endl;
            #endif

if((r_stream_length > 0 && s_window_length > 0) || (s_stream_length > 0 && r_window_length > 0)){
//创建r_stream、s_stream、r_window、s_window动态缓冲区
if(r_stream_length > 0 && s_window_length > 0){
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "krnl_r_stream_join : setArg..." <<std::endl;
            #endif
  if(move_host_r_window){
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(0, r_stream_length));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(1, s_window_length));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(2, r_stream_result_max));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(3, window_in_ms)); 
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(4, buffer_r_stream_result[flag]));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(5, buffer_r_stream[flag]));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(6, buffer_r_stream_info[flag]));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(7, buffer_s_window)); 
  }
  else{ //创建子缓冲区,包括当前的有效窗口部分
    cl_buffer_region region_s_slide_window = {sWindowStartAlign * BYTES_PER_TUPLE, sWindowEnd * BYTES_PER_TUPLE};
    //createSubBuffer(cl_mem_flags, cl_buffer_create_type, buffer_create_info * , err *)   
    cl::Buffer buffer_s_slide_window = buffer_s_window.createSubBuffer((cl_mem_flags)(CL_MEM_READ_ONLY), 
        CL_BUFFER_CREATE_TYPE_REGION, &region_s_slide_window, &err);  
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(0, r_stream_length));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(1, s_window_length));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(2, r_stream_result_max));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(3, window_in_ms)); 
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(4, buffer_r_stream_result[flag]));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(5, buffer_r_stream[flag]));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(6, buffer_r_stream_info[flag]));
    OCL_CHECK(err, err = krnl_r_stream_join.setArg(7, buffer_s_slide_window));     
  }
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "krnl_r_stream_join : migrate..." <<std::endl;
            #endif
  //迁移stream、window内存对象任务入队
  OCL_CHECK(err, err = qr.enqueueWriteBuffer(buffer_r_stream[flag], CL_FALSE, 0, 
        r_stream_length * BYTES_PER_TUPLE, &rWindow[rStreamVernier], NULL, 
        &migrate_stream_event[flag][_r_])); 
  if(move_host_r_window){//主机的s_window发生过迁移,将当前整个s_window迁移到设备buffer 0 地址
    OCL_CHECK(err, err = qr.enqueueWriteBuffer(buffer_s_window, CL_FALSE, 0, 
          s_window_length * BYTES_PER_TUPLE, &sWindow[sWindowStartAlign], NULL, 
          &migrate_window_event[flag][_r_])); 
    move_host_r_window = false;
  }
  else if(s_window_migrate_length > 0){//执行增量迁移
    OCL_CHECK(err, err = qr.enqueueWriteBuffer(buffer_s_window, CL_FALSE, sStreamVernierAlign * BYTES_PER_TUPLE, 
          s_window_migrate_length * BYTES_PER_TUPLE, &sWindow[sStreamVernierAlign], NULL, 
          &migrate_window_event[flag][_r_])); 
  }
}

if( s_stream_length > 0 && r_window_length > 0 ){
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "krnl_s_stream_join : setArg..." <<std::endl;
            #endif
  if(move_host_s_window){
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(0, s_stream_length));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(1, r_window_length));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(2, s_stream_result_max));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(3, window_in_ms)); 
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(4, buffer_s_stream_result[flag]));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(5, buffer_s_stream[flag]));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(6, buffer_s_stream_info[flag]));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(7, buffer_r_window));
  }
  else{ //创建子缓冲区,包括当前的有效窗口部分
    cl_buffer_region region_r_slide_window = {rWindowStartAlign * BYTES_PER_TUPLE, rWindowEnd * BYTES_PER_TUPLE};
    //createSubBuffer(cl_mem_flags, cl_buffer_create_type, buffer_create_info * , err *)   
    cl::Buffer buffer_r_slide_window = buffer_r_window.createSubBuffer((cl_mem_flags)(CL_MEM_READ_ONLY), 
        CL_BUFFER_CREATE_TYPE_REGION, &region_r_slide_window, &err);
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(0, s_stream_length));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(1, r_window_length));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(2, s_stream_result_max));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(3, window_in_ms)); 
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(4, buffer_s_stream_result[flag]));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(5, buffer_s_stream[flag]));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(6, buffer_s_stream_info[flag]));
    OCL_CHECK(err, err = krnl_s_stream_join.setArg(7, buffer_r_slide_window));
  }
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "krnl_s_stream_join : migrate..." <<std::endl;
            #endif
  //迁移stream、window内存对象任务入队
  OCL_CHECK(err, err = qs.enqueueWriteBuffer(buffer_s_stream[flag], CL_FALSE, 0, 
          s_stream_length * BYTES_PER_TUPLE, &sWindow[sStreamVernier], NULL, 
          &migrate_stream_event[flag][_s_])); 
  if(move_host_s_window){//s_window发生过迁移,将当前整个s_window迁移到设备buffer 0 地址
    OCL_CHECK(err, err = qs.enqueueWriteBuffer(buffer_r_window, CL_FALSE, 0, 
            r_window_length * BYTES_PER_TUPLE, &rWindow[rWindowStartAlign], NULL, 
            &migrate_window_event[flag][_s_])); 
    move_host_s_window = false;
  }
  else if(r_window_migrate_length > 0){//执行增量迁移
    OCL_CHECK(err, err = qs.enqueueWriteBuffer(buffer_r_window, CL_FALSE, rStreamVernierAlign * BYTES_PER_TUPLE, 
            r_window_migrate_length * BYTES_PER_TUPLE, &rWindow[rStreamVernierAlign], NULL, 
            &migrate_window_event[flag][_s_])); 
  }
}
  //移动流游标
  rStreamVernier = rWindowEnd;
  sStreamVernier = sWindowEnd;
}//if(至少一边需要连接)

//根据游标淘汰窗口元组
long long latest_ts = 0;
if(ctrl_order_preserving){
  if((rStreamVernier - rWindowStart) > 0){
      latest_ts = rWindow[rStreamVernier - 1].timestamp >> 20;
      while((latest_ts - (rWindow[rWindowStart].timestamp >> 20)) > window_length_in_ms){
          ++rWindowStart;
          if(rWindowStart >= rStreamVernier) break;
      }
  }
  if((sStreamVernier - sWindowStart) > 0){
      latest_ts = sWindow[sStreamVernier - 1].timestamp >> 20;
      while((latest_ts - (sWindow[sWindowStart].timestamp >> 20)) > window_length_in_ms){
          ++sWindowStart;
          if(sWindowStart >= sStreamVernier) break;
      }
  }
}
else{
  if((rStreamVernier - rWindowStart) > 0){
      latest_ts = rWindow[rStreamVernier - 1].timestamp;
      while((latest_ts - rWindow[rWindowStart].timestamp) > window_length_in_ms){
          ++rWindowStart;
          if(rWindowStart >= rStreamVernier) break;
      }
  }
  if((sStreamVernier - sWindowStart) > 0){
      latest_ts = sWindow[sStreamVernier - 1].timestamp;
      while((latest_ts - sWindow[sWindowStart].timestamp) > window_length_in_ms){
          ++sWindowStart;
          if(sWindowStart >= sStreamVernier) break;
      }
  }
}


//从post收回rflag的result_buffer
if(result_posting[rflag][_r_] || result_posting[rflag][_s_]){
  bool recover_buffer = false;
  while(1){
    if(!recover_buffer){
      std::lock_guard<std::mutex> mtx_locker(synchronization_join_post); //访问同步区
      if(_complete_ == post_type && post_flag == rflag){
        post_type = _invalid_;
        post_r_valid = false;
        post_s_valid = false;
        post_flag = 0;
        recover_buffer = true;
      }          
    }
    //稍微延迟时间,避免过于频繁阻塞post线程
    if(recover_buffer) break;
    long unsigned int s = (random_delay() % 10000);
    long unsigned int tmp = 0;
    for (size_t i = 0; i < s; i++){ tmp = i; tmp = tmp * 1997;}
  }
  result_posting[rflag][_r_] = false;
  result_posting[rflag][_s_] = false;     
}

if(result_reading[flag][_r_]){  //读阻塞
  OCL_CHECK(err, err = read_result_events[flag][_r_].wait());
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "read_result_events["<<flag<<"][_r_].wait() return" <<std::endl;
            #endif
}
if(result_reading[flag][_s_]){  //读阻塞
  OCL_CHECK(err, err = read_result_events[flag][_s_].wait());
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "read_result_events["<<flag<<"][_s_].wait() return" <<std::endl;
            #endif
}
if(result_reading[flag][_r_] || result_reading[flag][_s_]){
  std::lock_guard<std::mutex> mtx_locker(synchronization_join_post); //写入post指令
  if(result_reading[flag][_r_]){
    result_reading[flag][_r_] = false;
    result_posting[flag][_r_] = true;
    rstream_result_address = &(*pResultArray[flag][_r_])[0];
    rstream_post_num = (*pInfoArray[flag][_r_])[0].data[0];
    post_r_valid = true;
  }
  if(result_reading[flag][_s_]){
    result_reading[flag][_s_] = false;
    result_posting[flag][_s_] = true;
    sstream_result_address = &(*pResultArray[flag][_s_])[0];  
    sstream_post_num = (*pInfoArray[flag][_s_])[0].data[0];
    post_s_valid = true;
  }
  post_flag = flag;
  post_type = _post_;
}

if((r_stream_length > 0 && s_window_length > 0) || (s_stream_length > 0 && r_window_length > 0)){
//创建r_stream、s_stream、r_window、s_window动态缓冲区
if(r_stream_length > 0 && s_window_length > 0){
  //启动内核任务入队  
  wait_migrate_list_r.push_back(migrate_stream_event[flag][_r_]);
  wait_migrate_list_r.push_back(migrate_window_event[flag][_r_]);
  OCL_CHECK(err, err = qr.enqueueNDRangeKernel(krnl_r_stream_join, 0, 1, 1, &wait_migrate_list_r,
                                              &kernel_events[flag][_r_]));
  //读回info对象任务入队

  wait_calculate_list_r.push_back(kernel_events[flag][_r_]);
  OCL_CHECK(err, err = qr.enqueueMigrateMemObjects(
      {buffer_r_stream_info[flag]}, CL_MIGRATE_MEM_OBJECT_HOST, &wait_calculate_list_r, &read_info_events[flag][_r_]));
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "stream_computing["<<flag<<"][_r_] = true." <<std::endl;
            #endif
  stream_computing[flag][_r_] = true;     
}

if( s_stream_length > 0 && r_window_length > 0 ){   
  //启动内核任务入队
  wait_migrate_list_s.push_back(migrate_stream_event[flag][_s_]);
  wait_migrate_list_s.push_back(migrate_window_event[flag][_s_]);
  OCL_CHECK(err, err = qs.enqueueNDRangeKernel(krnl_s_stream_join, 0, 1, 1, &wait_migrate_list_s,
                                              &kernel_events[flag][_s_]));
  //读回info对象任务入队
  wait_calculate_list_s.push_back(kernel_events[flag][_s_]);
  OCL_CHECK(err, err = qs.enqueueMigrateMemObjects(
      {buffer_s_stream_info[flag]}, CL_MIGRATE_MEM_OBJECT_HOST, &wait_calculate_list_s, &read_info_events[flag][_s_]));
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "stream_computing["<<flag<<"][_s_] = true." <<std::endl;
            #endif
  stream_computing[flag][_s_] = true;  
}
}//if(至少一边需要连接)

            #ifdef RUN_SIMULATION  
                LOG << DEBUG << "Start read queue..."
                << "\n  read_fifo_count= ["<< read_fifo_count <<"] " 
                << "\n  rWindowStart   = ["<< rWindowStart <<"] "
                << "\n  rWindowEnd     = ["<< rWindowEnd <<"] "
                << "\n  rStreamVernier = ["<< rStreamVernier <<"] "
                << "\n  sWindowStart   = ["<< sWindowStart <<"] "
                << "\n  sWindowEnd     = ["<< sWindowEnd <<"] "
                << "\n  sStreamVernier = ["<< sStreamVernier <<"] "<< std::endl;
            #endif

//检查队列新元组并读入，但需在最大时延要求的一半内

long long now_ts = get_ts();
long long read_to_ts =  last_read_queue_ts + 0.6*(now_ts - last_read_queue_ts) + (max_join_delay_in_ms >> 1);

bool queue_read_empty = false;
long long tuple_ts = 0;
long long rid = 0;
long long sid = 0;
while(1){
    Line temp;
    if(tupleReadBuffer.try_pop(temp)){
        read_fifo_count++;
        if(temp.is_r){
            if(rWindowEnd == R_WINDOW_BUFFER_SIZE){ //窗口到达右边界则将整个窗口左移
                LOG << DEBUG << "rWindow reach right bound." <<std::endl;
                memcpy(&rWindow[0],&rWindow[rWindowStart],(rWindowEnd - rWindowStart)*sizeof(RTuple));
                rStreamVernier = rStreamVernier - rWindowStart;
                rWindowEnd = rWindowEnd - rWindowStart;
                rWindowStart = 0;
                move_host_r_window = true;
            }
            if(ctrl_order_preserving)
            temp.timestamp = (temp.timestamp << 20) | rid;
            ++rid;
            rWindow[rWindowEnd] = Line_to_RTuple(temp);
            ++rWindowEnd;
            if(rid + 1 >= SINK_BUCKETS) break;
        }
        else{
            if(sWindowEnd == S_WINDOW_BUFFER_SIZE){ //窗口到达右边界则将整个窗口左移
                LOG << DEBUG << "sWindow reach right bound." <<std::endl;
                memcpy(&sWindow[0],&sWindow[sWindowStart],(sWindowEnd - sWindowStart)*sizeof(STuple));
                sStreamVernier = sStreamVernier - sWindowStart;
                sWindowEnd = sWindowEnd - sWindowStart;
                sWindowStart = 0;
                move_host_s_window = true;
            }
            if(ctrl_order_preserving)
            temp.timestamp = (temp.timestamp << 20) | sid;
            ++sid;
            sWindow[sWindowEnd] = Line_to_STuple(temp);
            ++sWindowEnd; 
            if(sid + 1 >= SINK_BUCKETS) break;           
        }
    }
    else{   //稍微延迟时间,避免过于频繁阻塞读入队列
        queue_read_empty = true;
        long unsigned int s = (random_delay() % 10000);
        long unsigned int tmp = 0;
        for (size_t i = 0; i < s; i++){ tmp = i; tmp = tmp * 1997;}
    }
    if((get_ts() - ts_reminder) > 10000){
        ts_reminder = get_ts();
        LOG << DEBUG 
        << "\n  read_fifo_count= ["<< read_fifo_count <<"] " 
        << "\n  rWindowStart   = ["<< rWindowStart <<"] "
        << "\n  rWindowEnd     = ["<< rWindowEnd <<"] "
        << "\n  rStreamVernier = ["<< rStreamVernier <<"] "
        << "\n  sWindowStart   = ["<< sWindowStart <<"] "
        << "\n  sWindowEnd     = ["<< sWindowEnd <<"] "
        << "\n  sStreamVernier = ["<< sStreamVernier <<"] "
        << "\n  run time       = ["<< get_ts() -  initial_ts<<"] "<< std::endl;
    }
    if(get_ts() > read_to_ts && (queue_read_empty || tuple_ts > read_to_ts)) break;
}//end for read new tuple loop

last_read_queue_ts = read_to_ts;
loop_num++;
if(loop_num >= 16){
  cout<< "  run time     = ["<< get_ts() -  initial_ts<<"] "<< std::endl;
  loop_num = 0;
}

if(stream_computing[rflag][_r_]){
    OCL_CHECK(err, err = read_info_events[rflag][_r_].wait());
      #ifdef RUN_SIMULATION
      LOG << DEBUG << "read_info_events["<<rflag<<"][_r_].wait() return" <<std::endl;
      #endif
}
if(stream_computing[rflag][_s_]){
    OCL_CHECK(err, err = read_info_events[rflag][_s_].wait());
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "read_info_events["<<rflag<<"][_s_].wait() return" <<std::endl;
            #endif
}

//The opposite ping-pong buffer result read
if(stream_computing[rflag][_r_]){
  unsigned int rStream_result_num = (*pInfoArray[rflag][_r_])[0].data[0];
            #ifdef RUN_SIMULATION
            LOG << DEBUG << "stream_computing["<<rflag<<"][_r_].result_num = ["<< rStream_result_num <<"]" <<std::endl;
            #endif
  if(rStream_result_num > 0){
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "enqueueReadBuffer["<<rflag<<"][_r_],rStream_result_num =["<<rStream_result_num<<"]" <<std::endl;
            #endif
    result_reading[rflag][_r_] = true;
    OCL_CHECK(err, err = qr.enqueueReadBuffer(buffer_r_stream_result[rflag], CL_FALSE, 0, 
        rStream_result_num * BYTES_PER_TUPLE, &(*pResultArray[rflag][_r_])[0], NULL, 
        &read_result_events[rflag][_r_]));      
  }
  stream_computing[rflag][_r_] = false;

}
if(stream_computing[rflag][_s_]){
  unsigned int sStream_result_num = (*pInfoArray[rflag][_s_])[0].data[0];
            #ifdef RUN_SIMULATION
            LOG << DEBUG << "stream_computing["<<rflag<<"][_s_].result_num = ["<< sStream_result_num <<"]" <<std::endl;
            #endif
  if(sStream_result_num > 0){
            #ifdef RUN_SIMULATION  
            LOG << DEBUG << "enqueueReadBuffer["<<rflag<<"][_s_],sStream_result_num =["<<sStream_result_num<<"]" <<std::endl;
            #endif
    result_reading[rflag][_s_] = true;
    OCL_CHECK(err, err = qs.enqueueReadBuffer(buffer_s_stream_result[rflag], CL_FALSE, 0, 
        sStream_result_num * BYTES_PER_TUPLE, &(*pResultArray[rflag][_s_])[0], NULL, 
        &read_result_events[rflag][_s_]));
  }
  stream_computing[rflag][_s_] = false;
}

//检查控制命令是否退出    
if(ctrl_joiner_exit) {
    joiner_online_status = false;
    if(ctrl_joiner_exit)
    LOG << DEBUG << "ctrl_joiner_exit, Joiner Offline." << std::endl;
    printf("Waiting Finish...\n");
    #ifdef USE_FPGA
    OCL_CHECK(err, err = qr.flush());
    OCL_CHECK(err, err = qs.flush());
    OCL_CHECK(err, err = qr.finish());
    OCL_CHECK(err, err = qs.finish());
    #endif
    break;
}


flag = rflag;

}//end for while
}//end for joinThread
