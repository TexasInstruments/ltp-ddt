import fcntl                                                                
import os                                                                   
import weakref                                                              
import ctypes                                                                                                                
from ctypes import sizeof

_IOC_NRBITS = 8
_IOC_TYPEBITS = 8
_IOC_SIZEBITS = 14
_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS
_IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS
_IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS

_IOC_NONE = 0
_IOC_WRITE = 1
_IOC_READ = 2

def _IOC(iodir, iotype, nr, size):  # pylint: disable=invalid-name
    return ((((iodir << _IOC_DIRSHIFT) | (ord(iotype) << _IOC_TYPESHIFT)) | (nr << _IOC_NRSHIFT)) | (size << _IOC_SIZESHIFT))

def IO(iotype, nr):  # pylint: disable=invalid-name
    return _IOC (_IOC_NONE, iotype, nr, 0)

def IOR(iotype, nr, size):  # pylint: disable=invalid-name
    return _IOC (_IOC_READ, iotype, nr, sizeof(size))

def IOW(iotype, nr, size):  # pylint: disable=invalid-name
    return _IOC (_IOC_WRITE, iotype, nr, sizeof(size))

def IOWR(iotype, nr, size):  # pylint: disable=invalid-name
    return _IOC ((_IOC_READ | _IOC_WRITE), iotype, nr, sizeof(size))



__all__ = ['DMAHeap', 'DMAHeapBuffer']

# pylint: disable=invalid-name
class struct_dma_heap_allocation_data(ctypes.Structure):
    __slots__ = ['len', 'fd', 'fd_flags', 'heap_flags']
    _fields_ = [('len', ctypes.c_uint64),
                ('fd', ctypes.c_uint32),
                ('fd_flags', ctypes.c_uint32),
                ('heap_flags', ctypes.c_uint64)]

DMA_HEAP_IOC_MAGIC = 'H'

DMA_HEAP_IOCTL_ALLOC = IOWR(DMA_HEAP_IOC_MAGIC, 0x0, struct_dma_heap_allocation_data)


class DMAHeap:
    def __init__(self, name: str):
        self.fd = os.open(f'/dev/dma_heap/{name}', os.O_CLOEXEC | os.O_RDWR)

        weakref.finalize(self, os.close, self.fd)

    def alloc(self, length: int):
        # pylint: disable=attribute-defined-outside-init
        buf_data = struct_dma_heap_allocation_data()
        buf_data.len = length
        buf_data.fd_flags = os.O_CLOEXEC | os.O_RDWR
        fcntl.ioctl(self.fd, DMA_HEAP_IOCTL_ALLOC, buf_data, True)

        return DMAHeapBuffer(buf_data.fd, buf_data.len)


class DMAHeapBuffer:
    def __init__(self, fd: int, length: int):
        self.fd = fd
        self.length = length
        weakref.finalize(self, os.close, self.fd)