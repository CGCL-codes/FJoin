
#include "./head.hpp"

using namespace std;

int initial_run_join = 0;
Logger LOG = Logger("/home/llt/workspace2/join_hw/src/log/log_debug");

int main(int argc, char **argv) 
{
    char * binaryFile;
	if (argc != 2) {
	    std::cout << "Usage: " << argv[0] << " <XCLBIN File>" << std::endl;
	    return EXIT_FAILURE;
	}
	binaryFile = argv[1];
    long long init_ts = get_ts();
    long long now_ts = 0;
    cout<<"Main Start ";
    cout<<"ts = ["<<get_date_ts()<<"]."<<endl;
    std::thread _ParaCtrlThread(ParaCtrlThread,1); 
    //等待初始化配置结束
    while(0 == initial_run_join){
        long unsigned int s = 1997;
        long unsigned int tmp = 0;
        for (size_t i = 0; i < s; i++){ tmp = i; tmp = tmp * 1997;}
        now_ts = get_ts();
        if(now_ts - init_ts > 60000){//60s超时退出
            LOG << DEBUG <<"ParaCtrlThread Timeout, Main() Exit."<< std::endl;
            cout<<"ParaCtrlThread Timeout, Main Exit Error, ts = ["<<get_date_ts()<<"]."<<endl;
            return -1;
        }
    }
    if(1 != initial_run_join){
        _ParaCtrlThread.join();
        LOG << DEBUG <<"ParaCtrlThread Error, Main() Exit."<< std::endl;
        cout<<"ParaCtrlThread Error, Main Exit Error, ts = ["<<get_date_ts()<<"]."<<endl;
        return -1;
    }
    LOG << DEBUG << "Init OK, ts = ["<<get_date_ts()<<"]."<< std::endl;   
    std::thread _SourceThread(SourceThread, 2); 
    std::thread _PostStatisticsThread(PostStatisticsThread,3);
    std::thread _JoinThread(JoinThread, binaryFile, 4);
    _JoinThread.join();      
    _SourceThread.join();
    _PostStatisticsThread.join();
    _ParaCtrlThread.join();
    LOG << DEBUG <<"Main Exit Successful, ts = ["<<get_date_ts()<<"]."<< std::endl;
    cout<<"Main Exit Successful, ts = ["<<get_date_ts()<<"]."<<endl;
	return 0;
}
