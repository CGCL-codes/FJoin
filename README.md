# FJoin: an FPGA-based parallel accelerator for stream join

FJoin is an FPGA-based parallel accelerator for stream which leverages a large number of basic join units connected in series to form a deep join pipeline to achieve large-scale parallelism.FJoin can do High-Parallel Flow Join, in which data of the join window can flow through once to complete all join calculations after loading multiple stream tuples. The host CPU and FPGA device coordinate control, divide the continuous stream join calculation into independent small-batch tasks and efficiently ensure completeness of parallel stream join.  FJoin is implemented on a platform equipped with an FPGA accelerator card.The test results based on large-scale real data sets show that FJoin can increase the join calculation speed by 16 times using a single FPGA accelerator card and reach 5 times system throughput compared with the current best stream join system deployed on a 40-node cluster, and latency meets the real-time stream processing requirements.

# Introduction

# FJoin architecture
![image](https://github.com/Leomrlin/FJoin/blob/main/images/FJoin_img_arch.PNG)  
The overview of FJoin is shown in the picture. The system is divided into the upper part of the host-side software and the lower part of the device-side hardware. The hardware part includes the pipeline state machine(FSM) in each FPGA, and the memory access interface(Mem I/ F), and a deep connection pipeline composed of a large number of basic join units in series. The software part includes a stream join task scheduler(Task Scheduler), a join comleteness control module(Comleteness Controller) in which generates join calculation batch tasks, and a result post-processing module(Post-Process Module), and a management thread corresponding to each FPGA join pipeline.

# Basic join unit
![image](https://github.com/Leomrlin/FJoin/blob/main/images/FJoin_img_basic_join_unit.PNG)  
The structure of the basic join unit is shown in the picture, which contains the join logic that can be customized using RTL, three streams of stream tuples, window tuples, and result tuples passed from front to back, the clear and stall control signals passed by stages, and a join status register.

# How to use?

# Evaluation Result
![image](https://github.com/Leomrlin/FJoin/blob/main/images/FJoin_img_evaluation.PNG)  
The direct manifestation of processing capacity of the stream join system is number of join calculations completed per unit of time. The picture on the left is a real-time comparison of the number of join calculations completed per second between FJoin and the distributed stream join system BiStream. We use the data set of Didi Chuxing and the corresponding join predicate, the sliding time window size is set to 180 seconds. The results show that FJoin with 1024 basic join units can complete more than 100 billion join predicate calculations per second. However, BiStream which runs in a 40-node cluster with 512 CPUs completes join predicate calculations about 6 billion times per second. From the perspective of connection predicate calculations, FJoin achieves a speedup of about 17.  

The picture on the right compares the real-time throughput between FJoin and BiStream. This test uses the data set of the network traffic trajectory and the corresponding join predicate, and the sliding time window size is set to 15 seconds. We also divided into multiple tests to increase the input stream rate to test system Throughput value. Compared with the BiStream system with 512 CPU cores, FJoin with 1024 basic join units can reach 5x real-time throughput. In addition, compared with the same 512 unit system scale, the throughput of FJoin is increased to about 4x.  

# Publication
If you want to know more detailed information, please refer to this paper:  
The paper is being reviewed by Sci Sin Inform.

# Authors and Copyright
FJoin is developed in National Engineering Research Center for Big Data Technology and System, Cluster and Grid Computing Lab, Services Computing Technology and System Lab, School of Computer Science and Technology, Huazhong University of Science and Technology, Wuhan, China by Litao Lin (litaolin@hust.edu.cn), Hanhua Chen (chen@hust.edu.cn), Hai Jin (hjin@hust.edu.cn).

Copyright (C) 2021, [STCS & CGCL](http://grid.hust.edu.cn/) and [Huazhong University of Science and Technology](https://www.hust.edu.cn/).
