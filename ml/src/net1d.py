"""
Net1D: 1D CNN with Squeeze-and-Excitation for ECG classification.
From PKUDigitalHealth/ECGFounder (MIT License).
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


class MyConv1dPadSame(nn.Module):
    def __init__(self, in_channels, out_channels, kernel_size, stride, groups=1):
        super().__init__()
        self.in_channels = in_channels
        self.out_channels = out_channels
        self.kernel_size = kernel_size
        self.stride = stride
        self.conv = nn.Conv1d(in_channels, out_channels, kernel_size, stride, groups=groups)

    def forward(self, x):
        in_dim = x.shape[-1]
        out_dim = (in_dim + self.stride - 1) // self.stride
        p = max(0, (out_dim - 1) * self.stride + self.kernel_size - in_dim)
        pad_left = p // 2
        pad_right = p - pad_left
        x = F.pad(x, (pad_left, pad_right), "constant", 0)
        return self.conv(x)


class MyMaxPool1dPadSame(nn.Module):
    def __init__(self, kernel_size):
        super().__init__()
        self.kernel_size = kernel_size
        self.max_pool = nn.MaxPool1d(kernel_size=kernel_size)

    def forward(self, x):
        p = max(0, self.kernel_size - 1)
        pad_left = p // 2
        pad_right = p - pad_left
        x = F.pad(x, (pad_left, pad_right), "constant", 0)
        return self.max_pool(x)


class Swish(nn.Module):
    def forward(self, x):
        return x * torch.sigmoid(x)


class BasicBlock(nn.Module):
    def __init__(self, in_channels, out_channels, ratio, kernel_size, stride,
                 groups, downsample, is_first_block=False, use_bn=True, use_do=True):
        super().__init__()
        self.in_channels = in_channels
        self.out_channels = out_channels
        self.downsample = downsample
        self.stride = stride if downsample else 1
        self.is_first_block = is_first_block
        self.use_bn = use_bn
        self.use_do = use_do
        middle = int(out_channels * ratio)

        self.bn1 = nn.BatchNorm1d(in_channels)
        self.activation1 = Swish()
        self.do1 = nn.Dropout(p=0.5)
        self.conv1 = MyConv1dPadSame(in_channels, middle, 1, 1, 1)

        self.bn2 = nn.BatchNorm1d(middle)
        self.activation2 = Swish()
        self.do2 = nn.Dropout(p=0.5)
        self.conv2 = MyConv1dPadSame(middle, middle, kernel_size, self.stride, groups)

        self.bn3 = nn.BatchNorm1d(middle)
        self.activation3 = Swish()
        self.do3 = nn.Dropout(p=0.5)
        self.conv3 = MyConv1dPadSame(middle, out_channels, 1, 1, 1)

        # Squeeze-and-Excitation
        r = 2
        self.se_fc1 = nn.Linear(out_channels, out_channels // r)
        self.se_fc2 = nn.Linear(out_channels // r, out_channels)
        self.se_activation = Swish()

        if self.downsample:
            self.max_pool = MyMaxPool1dPadSame(kernel_size=self.stride)

    def forward(self, x):
        identity = x
        out = x

        if not self.is_first_block:
            if self.use_bn:
                out = self.bn1(out)
            out = self.activation1(out)
            if self.use_do:
                out = self.do1(out)
        out = self.conv1(out)

        if self.use_bn:
            out = self.bn2(out)
        out = self.activation2(out)
        if self.use_do:
            out = self.do2(out)
        out = self.conv2(out)

        if self.use_bn:
            out = self.bn3(out)
        out = self.activation3(out)
        if self.use_do:
            out = self.do3(out)
        out = self.conv3(out)

        # SE attention
        se = out.mean(-1)
        se = self.se_fc1(se)
        se = self.se_activation(se)
        se = self.se_fc2(se)
        se = torch.sigmoid(se)
        out = torch.einsum('abc,ab->abc', out, se)

        if self.downsample:
            identity = self.max_pool(identity)
        if self.out_channels != self.in_channels:
            identity = identity.transpose(-1, -2)
            ch1 = (self.out_channels - self.in_channels) // 2
            ch2 = self.out_channels - self.in_channels - ch1
            identity = F.pad(identity, (ch1, ch2), "constant", 0)
            identity = identity.transpose(-1, -2)

        out += identity
        return out


class BasicStage(nn.Module):
    def __init__(self, in_channels, out_channels, ratio, kernel_size, stride,
                 groups, i_stage, m_blocks, use_bn=True, use_do=True):
        super().__init__()
        self.block_list = nn.ModuleList()
        for i_block in range(m_blocks):
            is_first = (i_stage == 0 and i_block == 0)
            if i_block == 0:
                tmp_block = BasicBlock(
                    in_channels, out_channels, ratio, kernel_size,
                    stride, groups, downsample=True,
                    is_first_block=is_first, use_bn=use_bn, use_do=use_do)
            else:
                tmp_block = BasicBlock(
                    out_channels, out_channels, ratio, kernel_size,
                    1, groups, downsample=False,
                    is_first_block=False, use_bn=use_bn, use_do=use_do)
            self.block_list.append(tmp_block)

    def forward(self, x):
        for block in self.block_list:
            x = block(x)
        return x


class Net1D(nn.Module):
    """
    1D CNN for ECG classification.
    Input:  (batch, in_channels, length)
    Output: (batch, n_classes)
    """
    def __init__(self, in_channels, base_filters, ratio, filter_list,
                 m_blocks_list, kernel_size, stride, groups_width,
                 n_classes, use_bn=True, use_do=True, verbose=False):
        super().__init__()
        self.n_stages = len(filter_list)
        self.use_bn = use_bn

        self.first_conv = MyConv1dPadSame(in_channels, base_filters, kernel_size, stride=2)
        self.first_bn = nn.BatchNorm1d(base_filters)
        self.first_activation = Swish()

        self.stage_list = nn.ModuleList()
        in_ch = base_filters
        for i_stage in range(self.n_stages):
            out_ch = filter_list[i_stage]
            self.stage_list.append(BasicStage(
                in_ch, out_ch, ratio, kernel_size, stride,
                out_ch // groups_width, i_stage, m_blocks_list[i_stage],
                use_bn=use_bn, use_do=use_do))
            in_ch = out_ch

        self.dense = nn.Linear(in_ch, n_classes)

    def forward(self, x):
        out = self.first_conv(x)
        if self.use_bn:
            out = self.first_bn(out)
        out = self.first_activation(out)

        for stage in self.stage_list:
            out = stage(out)

        features = out.mean(-1)  # Global Average Pooling
        out = self.dense(features)
        return out
