# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

target_sources(DSXCore PRIVATE
  ConnectionTransport.swift
  NativeStream+Output.swift
  SocketChannel.swift
  SocketEndpoint.swift
  SocketListener.swift
  Stream.swift
  TransportError.swift
  WaitHandle.swift)
