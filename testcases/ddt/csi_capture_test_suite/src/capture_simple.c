/*
 * V4L2 video capture test
 * sets camera in test pattern mode and verifies capture
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <getopt.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>

#define CLEAR(x) memset(&(x), 0, sizeof(x))

#define MAX_NUM_TEST_PATTERN 5
#define SIZE_NAME 64

enum camera_type
{
    CAMERA_TYPE_IMX390,
    CAMERA_TYPE_IMX219,
    CAMERA_TYPE_OV5640
};

struct buffer
{
    void *start;
    size_t length;
};

struct test_pattern_info
{
    char tp_name[SIZE_NAME];
    int simple_check;
    int direct_compare;
};

struct camera_info
{
    enum camera_type ctype;
    char *camera_name;
    int width;
    int height;
    int num_tp;
    struct test_pattern_info tp[MAX_NUM_TEST_PATTERN];
};

static char *dev_name;
static char *subdev_name;
static char *camera_name;
// char reference_file[1000];
static int fd = -1;
static int fd_subdev = -1;
FILE* fd_ref_tp;
FILE* fd_ref_tp_temp;
char ref_file[200];
int test_pattern_val;
double fps = 0;
struct buffer *buffers;
struct timeval prev_ts;
static unsigned int n_buffers = 4;
static int frame_count = 60;
static int frame_simple_err_count = 0;
static int frame_direct_err_count = 0;
struct camera_info OV5640_info={CAMERA_TYPE_OV5640,"OV5640",640,480,5,{}};
struct camera_info IMX219_info={CAMERA_TYPE_IMX219,"IMX219",640,480,4,{}};
struct camera_info IMX390_info={CAMERA_TYPE_IMX390,"IMX390",1936,1100,5,{}};

static void errno_exit(const char *s)
{
    fprintf(stderr, "%s error %d, %s\\n", s, errno, strerror(errno));
    exit(EXIT_FAILURE);
}

static int xioctl(int fh, int request, void *arg)
{
    int r;

    do
    {
        r = ioctl(fh, request, arg);
    } while (-1 == r && EINTR == errno);

    return r;
}

/*
 * performs a simple line-line comparison of the test pattern
 * works fine for vertical/horizontal color bar patterns
 * ignore less than 10  line errors per frame, mainly due
 * to the border lines.
 */
static void verify_image_simple(const void *p, struct camera_info cam_name_struct)
{
    int line;
    int stat1, stat2, errcount = 0;
    int height=cam_name_struct.height;
    int width=cam_name_struct.width;
    for (line = 0; line < height/2; line++)
    {
        stat1 = memcmp(p + (line * width * 2), p + ((line + 2) * width * 2), width * 2);
        stat2 = memcmp(p + ((line + 1) * width * 2), p + ((line + 3) * width * 2), width * 2);
        if (stat1 || stat2)
            errcount++;
    }

    if (errcount / frame_count > 10)
        frame_simple_err_count++;

    fflush(stderr);
    fflush(stdout);
}

static void direct_compare_images(const void *p2,int size,struct camera_info cam_name_struct)
{
    FILE *p1=fd_ref_tp;
    int line;
    int stat1, errcount = 0;
    int height=cam_name_struct.height;
    int width=cam_name_struct.width;
    unsigned char buffer_ref[width*height*2];
    fread(&buffer_ref,sizeof(buffer_ref),1,p1);
    for (line = 0; line < height; line++)
    {
        int start=line*width*2;
        for(int wid_off=0;wid_off<width;wid_off++)
        {
            stat1=memcmp(buffer_ref+(start+wid_off),p2+(start+wid_off),1);
            if(stat1)
                errcount++;
        }
    }
    if((errcount/(float) size)*100 > 15)
        frame_direct_err_count+=1;
    fflush(stderr);
    fflush(stdout);
}

static int read_frame(int test_pattern_val,struct camera_info cam_name_struct)
{
    struct v4l2_buffer buf;
    double oldfps = fps;

    CLEAR(buf);

    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;

    if (-1 == xioctl(fd, VIDIOC_DQBUF, &buf))
    {
        switch (errno)
        {
        case EAGAIN:
            return 0;
        case EIO:
        default:
            errno_exit("VIDIOC_DQBUF");
        }
    }
    if (prev_ts.tv_sec || prev_ts.tv_usec)
    {
        fps = (buf.timestamp.tv_sec * 1000000 + buf.timestamp.tv_usec) - (prev_ts.tv_sec * 1000000 + prev_ts.tv_usec);
        fps = 1000000 / fps;
        fps = (fps + oldfps) / 2;
    }
    assert(buf.index < n_buffers);

    prev_ts.tv_sec = buf.timestamp.tv_sec;
    prev_ts.tv_usec = buf.timestamp.tv_usec;
    if(cam_name_struct.tp[test_pattern_val].simple_check==1)
        verify_image_simple(buffers[buf.index].start, cam_name_struct);
    if(cam_name_struct.tp[test_pattern_val].direct_compare==1)
        direct_compare_images(buffers[buf.index].start,buf.bytesused,cam_name_struct);
    if (-1 == xioctl(fd, VIDIOC_QBUF, &buf))
        errno_exit("VIDIOC_QBUF");

    return 1;
}

static void mainloop(int test_pattern_val,struct camera_info cam_name_struct)
{
    unsigned int count;

    unsigned int buff_cnt=0;

    count = frame_count;
    while (count-- > 0)
    {
        for (;;)
        {
            fd_set fds;
            struct timeval tv;
            int r;

            FD_ZERO(&fds);
            FD_SET(fd, &fds);
            tv.tv_sec = 10;
            tv.tv_usec = 0;
            r = select(fd + 1, &fds, NULL, NULL, &tv);

            if (-1 == r)
            {
                if (errno == EINTR)
                    continue;
                errno_exit("select");
            }

            if (r == 0)
            {
                fprintf(stderr, "select timeout\\n");
                exit(EXIT_FAILURE);
            }
            if (read_frame(test_pattern_val,cam_name_struct))
                break;
        }
        buff_cnt++;
    }
}

static void stop_capturing(void)
{
    enum v4l2_buf_type type;

    type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (-1 == xioctl(fd, VIDIOC_STREAMOFF, &type))
        errno_exit("VIDIOC_STREAMOFF");
}

static void start_capturing(void)
{
    unsigned int i;
    enum v4l2_buf_type type;

    for (i = 0; i < n_buffers; ++i)
    {
        struct v4l2_buffer buf;

        CLEAR(buf);
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        if (-1 == xioctl(fd, VIDIOC_QBUF, &buf))
            errno_exit("VIDIOC_QBUF");
    }
    type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (-1 == xioctl(fd, VIDIOC_STREAMON, &type))
        errno_exit("VIDIOC_STREAMON");
}

static void uninit_device(void)
{
    unsigned int i;

    for (i = 0; i < n_buffers; ++i)
        if (-1 == munmap(buffers[i].start, buffers[i].length))
            errno_exit("munmap");
    free(buffers);
}

static void init_mmap(void)
{
    struct v4l2_requestbuffers req;

    CLEAR(req);

    req.count = 4;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;

    if (-1 == xioctl(fd, VIDIOC_REQBUFS, &req))
    {
        if (errno == EINVAL)
        {
            fprintf(stderr, "%s does not support memory mapping",
                    dev_name);
            exit(EXIT_FAILURE);
        }
        else
        {
            errno_exit("VIDIOC_REQBUFS");
        }
    }

    if (req.count < 2)
    {
        fprintf(stderr, "Insufficient buffer memory on %s\\n",
                dev_name);
        exit(EXIT_FAILURE);
    }

    buffers = calloc(req.count, sizeof(*buffers));

    if (!buffers)
    {
        fprintf(stderr, "Out of memory\\n");
        exit(EXIT_FAILURE);
    }

    for (n_buffers = 0; n_buffers < req.count; ++n_buffers)
    {
        struct v4l2_buffer buf;

        CLEAR(buf);

        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = n_buffers;

        if (-1 == xioctl(fd, VIDIOC_QUERYBUF, &buf))
            errno_exit("VIDIOC_QUERYBUF");

        buffers[n_buffers].length = buf.length;
        buffers[n_buffers].start =
            mmap(NULL /* start anywhere */,
                 buf.length,
                 PROT_READ | PROT_WRITE /* required */,
                 MAP_SHARED /* recommended */,
                 fd, buf.m.offset);

        if (buffers[n_buffers].start == MAP_FAILED)
            errno_exit("mmap");
    }
}

static void change_test_pattern(int fd_subdev,int test_pattern_val)
{
    struct v4l2_control ctrl;
    memset(&ctrl,0,sizeof(ctrl));
    ctrl.id=V4L2_CID_TEST_PATTERN;
    ctrl.value=test_pattern_val;
    ioctl(fd_subdev,VIDIOC_S_CTRL,&ctrl);
}

static void get_tp_ref_file(char *test_data_file, int test_pattern_val,
                            char *sensor_name)
{
    char *ltproot = getenv("LTPROOT");
    snprintf(test_data_file, 200,
             "%s/testcases/data/%s/v4l2cap_%s_testpattern_%d.bin", ltproot,
             TCID, sensor_name, test_pattern_val);
}

static void init_device(char *camera_name,int test_pattern_val)
{
    struct v4l2_capability cap;
    if (-1 == xioctl(fd, VIDIOC_QUERYCAP, &cap))
    {
        if (errno == EINVAL)
        {
            fprintf(stderr, "%s is no V4L2 device\\n",
                    dev_name);
            exit(EXIT_FAILURE);
        }
        else
        {
            errno_exit("VIDIOC_QUERYCAP");
        }
    }

    if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE))
    {
        fprintf(stderr, "%s is no video capture device\\n", dev_name);
        exit(EXIT_FAILURE);
    }

    if (!(cap.capabilities & V4L2_CAP_STREAMING))
    {
        fprintf(stderr, "%s does not support streaming i/o\\n",
                dev_name);
        exit(EXIT_FAILURE);
    }
    if(strcmp(camera_name,"OV5640")==0)
    {
        get_tp_ref_file(ref_file, test_pattern_val, "ov5640");
        OV5640_info.tp[test_pattern_val].simple_check=1;
        OV5640_info.tp[test_pattern_val].direct_compare=1;

        fd_ref_tp = fopen(ref_file, "rb");
        if (NULL == fd_ref_tp)
        {
            fprintf(stderr, "Cannot open '%s': %d, %s\\n",
                    ref_file, errno, strerror(errno));
            exit(EXIT_FAILURE);
        }
    } else if(strcmp(camera_name,"IMX219")==0) {
        get_tp_ref_file(ref_file, test_pattern_val, "imx219");
        IMX219_info.tp[test_pattern_val].simple_check=1;
        IMX219_info.tp[test_pattern_val].direct_compare=1;

        fd_ref_tp = fopen(ref_file, "rb");
        if (NULL == fd_ref_tp)
        {
            fprintf(stderr, "Cannot open '%s': %d, %s\\n",
                    ref_file, errno, strerror(errno));
            exit(EXIT_FAILURE);
        }
    } else if(strcmp(camera_name,"IMX390")==0) {
        get_tp_ref_file(ref_file, test_pattern_val, "imx390");
        IMX390_info.tp[test_pattern_val].simple_check=1;
        IMX390_info.tp[test_pattern_val].direct_compare=1;

        fd_ref_tp = fopen(ref_file, "rb");
        if (NULL == fd_ref_tp)
        {
            fprintf(stderr, "Cannot open '%s': %d, %s\\n",
                    ref_file, errno, strerror(errno));
            exit(EXIT_FAILURE);
        }
    }
    change_test_pattern(fd_subdev,test_pattern_val);
    init_mmap();
}

static void close_device(void)
{
    change_test_pattern(fd_subdev,0);
    if (-1 == close(fd))
        errno_exit("close");
    if (-1 == close(fd_subdev))
        errno_exit("close");
    if (fclose(fd_ref_tp))
        perror("fclose error");
    fd = -1;
    fd_subdev = -1;

}

static void open_device(void)
{
    struct stat st;

    if (-1 == stat(dev_name, &st))
    {
        fprintf(stderr, "Cannot identify '%s': %d, %s\\n",
                dev_name, errno, strerror(errno));
        exit(EXIT_FAILURE);
    }

    if (!S_ISCHR(st.st_mode))
    {
        fprintf(stderr, "%s is no devicen", dev_name);
        exit(EXIT_FAILURE);
    }

    fd = open(dev_name, O_RDWR | O_NONBLOCK, 0);
    fd_subdev = open(subdev_name, O_RDWR | O_NONBLOCK, 0);
    if (-1 == fd)
    {
        fprintf(stderr, "Cannot open '%s': %d, %s\\n",
                dev_name, errno, strerror(errno));
        exit(EXIT_FAILURE);
    }
    if (-1 == fd_subdev)
    {
        fprintf(stderr, "Cannot open '%s': %d, %s\\n",
                subdev_name, errno, strerror(errno));
        exit(EXIT_FAILURE);
    }
}

static void usage(FILE *fp, char **argv)
{
    fprintf(fp,
            "Usage: %s [options]\n\n"
            "Version 1.3\n"
            "Options:\n"
            "-d | --device name   Video device name [%s]\n"
            "-s | --sub-device name   v4l2 subdev name [%s]\n"
            "-h | --help          Print this message\n"
            "",
            argv[0], dev_name, subdev_name);
}

static const char short_options[] = "d:s:t:n:h";

static const struct option
    long_options[] = {
        {"device", required_argument, NULL, 'd'},
        {"subdev", required_argument, NULL, 's'},
        {"camera_name", required_argument, NULL, 'n'},
        {"test_pattern_val", required_argument, NULL, 't'},
        {"help", no_argument, NULL, 'h'},
        {0, 0, 0, 0}};

int main(int argc, char **argv)
{  
    for (;;)
    {
        int idx;
        int c;

        c = getopt_long(argc, argv, short_options, long_options, &idx);

        if (-1 == c)
            break;

        switch (c)
        {
        case 0:
            break;
        case 'd':
            dev_name = optarg;
            break;
        case 's':
            subdev_name = optarg;
            break;
        case 'h':
            usage(stdout, argv);
            exit(EXIT_SUCCESS);
        case 't':
            test_pattern_val = atoi(optarg);
            break;
        case 'n':
            camera_name = optarg;
            break;
        default:
            usage(stderr, argv);
            exit(EXIT_FAILURE);
        }
    }

    fprintf(stdout, "Testing sensor=%s , dev=%s , subdev=%s\n", camera_name, dev_name, subdev_name);
    open_device();
    init_device(camera_name,test_pattern_val);
    start_capturing();
    if(strcmp(camera_name,"OV5640")==0)
    {
        mainloop(test_pattern_val,OV5640_info);
    }
    else if(strcmp(camera_name,"IMX390")==0)
    {
        mainloop(test_pattern_val,IMX390_info);
    }
    else if(strcmp(camera_name,"IMX219")==0)
    {
        mainloop(test_pattern_val,IMX219_info);
    }
    stop_capturing();
    uninit_device();
    close_device();
    fprintf(stdout, "Test Pattern:%d, Test %s, Total Frame captured = %d, Total Errors = %d, Average FPS = %f fps.\n", test_pattern_val, frame_simple_err_count > 0 ? "failed" : "passed",
            frame_count, frame_simple_err_count, fps);
    fprintf(stdout, "Test Pattern:%d, Test %s, Total Frame captured = %d, Total Errors = %d, Average FPS = %f fps.\n", test_pattern_val, ((frame_direct_err_count/(float)frame_count)*100>2) ? "failed" : "passed",
            frame_count, frame_direct_err_count, fps);
    
    if(frame_simple_err_count > 0 || ((frame_direct_err_count/(float)frame_count)*100>2))
        return -1;
    else
        return 0;
}
