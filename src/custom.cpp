#ifndef __CUSTOM__
#define __CUSTOM__
#include "./head.hpp"

RTuple Line_to_RTuple(const Line &l){
   RTuple t;
   t.latitude = stoi(l.values[2]);//latitude
   t.longtitude = stoi(l.values[1]);//longtitude
   t.timestamp = l.timestamp;
   return t;
}

STuple Line_to_STuple(const Line &l){
   STuple t;
   t.latitude = stoi(l.values[2]);//latitude
   t.longtitude = stoi(l.values[1]);//longtitude
   t.timestamp = l.timestamp;
   return t;
}

Line ResultTuple_to_Line(const ResultTuple &r){
   Line l;
   l.relation = "output";
   l.timestamp = get_ts();
   l.values.push_back(to_string(r.stream_timestamp));
   l.values.push_back(to_string(r.stream_longtitude));
   l.values.push_back(to_string(r.stream_latitude));
   l.values.push_back(to_string(r.window_timestamp));
   l.values.push_back(to_string(r.window_longtitude));
   l.values.push_back(to_string(r.window_latitude));
   return l;
}


 // RTuple Line_to_RTuple(const Line &l){
 //     RTuple t;
 //     t.src = stoul(l.values[0]);//latitude
 //     t.des = stoul(l.values[1]);//longtitude
 //     t.timestamp = l.timestamp;
 //     return t;
 // }

 // STuple Line_to_STuple(const Line &l){
 //     STuple t;
 //     t.src = stoul(l.values[0]);//latitude
 //     t.des = stoul(l.values[1]);//longtitude
 //     t.timestamp = l.timestamp;
 //     return t;
 // }

 // Line ResultTuple_to_Line(const ResultTuple &r){
 //     Line l;
 //     l.relation = "output";
 //     l.timestamp = get_ts();
 //     l.values.push_back(to_string(r.stream_timestamp));
 //     l.values.push_back(to_string(r.stream_src));
 //     l.values.push_back(to_string(r.stream_des));
 //     l.values.push_back(to_string(r.window_timestamp));
 //     l.values.push_back(to_string(r.window_src));
 //     l.values.push_back(to_string(r.window_des));
 //     return l;
 // }

#endif
