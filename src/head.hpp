
#ifndef __HEADHPP__
#define __HEADHPP__

//#define USE_CPU
#define USE_FPGA
//#define RUN_SIMULATION
#define RUN_HARDWARE

#include <random>
#include <algorithm>
#include <cstdio>
#include <vector>
#include <ctime>
#include <string>
#include <iostream>
#include <fstream>
#include <list>
#include <cassert>
#include <sstream>
#include <queue>  
#include <memory>  
#include <mutex>  
#include <thread>
#include <condition_variable>  
#include <sys/time.h>
#include <CL/cl_ext.h>
#include "./util/threadsafe_queue.hpp"
#include "./util/xcl2.hpp"

using namespace std;

//默认值设置
#define DEFAULT_SOURCE_SPEED 100
#define MAX_SUSTAINABLE_THROUPUT 200
#define DEFAULT_R_RATIO 1
#define DEFAULT_S_RATIO 1
#define DEFAULT_WIN_LEN_IN_MS 100000 //para_ctrl使用
#define R_WINDOW_BUFFER_SIZE 30000000
#define S_WINDOW_BUFFER_SIZE 30000000
#define MAX_STREAM_SIZE 1000000
#define RESULT_BUFFER_SIZE 10000000
#define DEFAULT_MAX_DELAY_IN_MS 200

#define REPORT_DELAY_FREQUENT 100000
#define REPOT_SOURCE_LINES_FREQUENT 100000

//代码宏
#define BYTES_PER_TUPLE 64
#define INTS_PER_TUPLE 16
#define INFO_BUFFER_SIZE 1
#define _r_ 0
#define _s_ 1
#define _invalid_ 0
#define _post_ 1
#define _complete_ 2

////////////////// CUSTOM HEAD ////////////////////////
////需要自定义的结构
struct RTuple{
   unsigned int latitude = 0;
   unsigned int longtitude = 0;
   long long timestamp = 0;
   unsigned int zero[16 - 4] = {0};
};
struct STuple{
   unsigned int latitude = 0;
   unsigned int longtitude = 0;
   long long timestamp = 0;
   unsigned int zero[16 - 4] = {0};
};

struct ResultTuple{
   unsigned int window_latitude = 0;
   unsigned int window_longtitude = 0;
   long long window_timestamp = 0;
   unsigned int stream_latitude = 0;
   unsigned int stream_longtitude = 0;
   long long stream_timestamp = 0;
   unsigned int zero[16 - 8] = {0};
};


 //需要自定义的结构
 // struct RTuple{
 //     unsigned int des = 0;
 //     unsigned int src = 0;
 //     long long timestamp = 0;
 //     unsigned int zero[16 - 4] = {0};
 // };
 // struct STuple{
 //     unsigned int des = 0;
 //     unsigned int src = 0;
 //     long long timestamp = 0;
 //     unsigned int zero[16 - 4] = {0};
 // };

 // struct ResultTuple{
 //     unsigned int window_des = 0;
 //     unsigned int window_src = 0;
 //     long long window_timestamp = 0;
 //     unsigned int stream_des = 0;
 //     unsigned int stream_src = 0;
 //     long long stream_timestamp = 0;
 //     unsigned int zero[16 - 8] = {0};
 // };

///////////////////////////////////////////////////////////
struct Line
{
    string relation = "";
    bool is_r = false;
    long long timestamp = 0;
    std::vector<std::string> values;
};

struct InfoTuple{ 
    unsigned int data[16] = {0};
};

RTuple Line_to_RTuple(const Line &l);
STuple Line_to_STuple(const Line &l);
Line ResultTuple_to_Line(const ResultTuple &r);

extern int initial_run_join;
void SourceThread(int);
void ParaCtrlThread(int);
extern long source_speed;
extern long r_ratio;
extern long s_ratio;
extern bool ctrl_source_exit;
extern bool source_error_offline;

void JoinThread(const char * , int);
extern bool joiner_online_status;
extern bool ctrl_joiner_exit;
extern long long read_fifo_count;
extern unsigned int window_length_in_ms;
extern unsigned int max_join_delay_in_ms;
extern threadsafe_queue<Line> tupleReadBuffer;

void PostStatisticsThread(int threadid);
extern std::mutex synchronization_join_post;
extern ResultTuple * rstream_result_address;
extern ResultTuple * sstream_result_address;
extern unsigned long rstream_post_num;
extern unsigned long sstream_post_num;
extern bool post_r_valid;
extern bool post_s_valid;
extern int post_flag;
extern int post_type;
extern bool ctrl_output_result_tuple;
extern bool ctrl_output_result_ts;
extern bool ctrl_output_result_delay;
extern bool ctrl_order_preserving;
extern bool ctrl_poster_exit;
extern const long long SINK_BUCKETS;
// Log levels
typedef enum {
  VERBOSE = 0,
  DEBUG,
  INFO,
  WARNING,
  ERROR,
  CRITICAL
} logger_level;

class Logger : public std::ostringstream {
public:
    Logger(const char *f);
    Logger(const std::string& f);
    Logger (const Logger &);
    Logger &operator= (const Logger &);
    ~Logger();
    
    
    void set_level(const logger_level& level);
    void set_default_line_level(const logger_level& level);
    void flush();
    template <typename T>
    Logger& operator<<(const T& t)
    {
    *static_cast<std::ostringstream *>(this) << t;
    return (*this);
    }
    
    Logger& operator<<(const logger_level& level);
    typedef Logger& (* LoggerManip)(Logger&);
    Logger& operator<<(LoggerManip m);
    
private:
    std::string get_time() const;
    inline const char* level_str(const logger_level& level);
    
    std::ofstream  _file;
    std::ostream&  _log; 
    logger_level   _level;
    logger_level   _line_level;
    logger_level   _default_line_level;
};


namespace std { 
    inline Logger& endl(Logger& out) 
    { 
    out.put('\n'); 
    out.flush(); 
    return (out); 
    } 
}


class FileReader{
private:
    const string DEFAULT_SPLIT_PATTERN = ",";
    string _filename;
    string _seperator;
    ifstream _infile;
    string readLine();
    std::vector<std::string> SplitString(const std::string& s, const std::string& seperator);
    void getIfstream();
    string trim(string &s);   
public:
    FileReader(string filename, string splitPunc);
    string getFilename();    
    bool good();
    std::vector<std::string> readLineAndSplit();
};

class FileWriter{
private:
    const string DEFAULT_SPLIT_PATTERN = ",";
    string _filename;
    string _seperator;
    ofstream _outfile;
    bool writeLine(std::string& line);
    string trim(const string &s);   
public:
    FileWriter(std::string filename,std::string seperator, bool overwrite);
    string getFilename();    
    bool good();
    bool constructLineAndWrite(std::vector<std::string> strings);
};



long long get_ts();
std::string get_date_ts();

#ifndef USE_FPGA
void r_join(
    const unsigned int r_stream_length, 
    const unsigned int s_window_length, 
    const unsigned int r_stream_result_max, 
    const unsigned int window_in_ms,
    ResultTuple *      r_stream_result,
    RTuple *           r_stream,
    InfoTuple *        r_stream_info,
    STuple *           s_window
) ;
void s_join(
    const unsigned int s_stream_length, 
    const unsigned int r_window_length, 
    const unsigned int s_stream_result_max,
    const unsigned int window_in_ms,
    ResultTuple *      s_stream_result,
    STuple *           s_stream,
    InfoTuple *        s_stream_info,
    RTuple *           r_window
) ;
#endif 

extern Logger LOG;
extern string R_NAME; 
extern string R_DATA; 
extern string S_NAME; 
extern string S_DATA; 
extern string W_NAME; 
extern string R_PUNC; 
extern string S_PUNC;
extern string W_PUNC;

#endif
