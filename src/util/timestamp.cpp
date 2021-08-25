#ifndef __TIMER__
#define __TIMER__
#include"../head.hpp"

std::string get_date_ts()
{
    struct tm *timeinfo;
    time_t rawtime;
    char *time_buf;
    
    time(&rawtime);
    timeinfo = localtime(&rawtime);
    time_buf = asctime(timeinfo);
    
    std::string ret(time_buf);
    if (!ret.empty() && ret[ret.length() - 1] == '\n') {
	ret.erase(ret.length()-1);
    }
    
    return (ret);
}

long long get_ts()
{
    time_t t= time(NULL);
    struct timeval tv;  
    gettimeofday(&tv,NULL);
    return ((long long)(t * 1000) + (long long)(tv.tv_usec >> 10));//返回近似毫秒时间戳
}

#endif