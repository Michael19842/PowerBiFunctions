// Function build for decompressing a Zip file even if the filelength is missing in the localheader
// More info on zip files here: https://en.wikipedia.org/wiki/ZIP_(file_format)
// Known limitation: If there is a comment appended to the central header then this function will fail. You can use a hex editor to find these comments at the end of the file wicht will be just readable text  
(ZipFile as binary) =>
    let
        //Load the file into a buffer
        ZipFileBuffer = Binary.Buffer(ZipFile),
        ZipFileSize = Binary.Length(ZipFileBuffer),
        //Constant values used in the query
        CentralHeaderSignature = 0x02014b50,
        CentralHeaderSize = 42,
        LocalHeaderSize = 30,
        // Predefined byteformats that are used many times over 
        Unsigned16BitLittleIEndian =
            BinaryFormat.ByteOrder(
                BinaryFormat.UnsignedInteger16,
                ByteOrder.LittleEndian
            ),
        Unsigned32BitLittleIEndian =
            BinaryFormat.ByteOrder(
                BinaryFormat.UnsignedInteger32,
                ByteOrder.LittleEndian
            ),
        // Definition of central directory header
        CentralDirectoryHeader =
            BinaryFormat.Record(
                [
                    Version = Unsigned16BitLittleIEndian,
                    VersionNeeded = Unsigned16BitLittleIEndian,
                    GeneralPurposeFlag = Unsigned16BitLittleIEndian,
                    CompressionMethod = Unsigned16BitLittleIEndian,
                    LastModifiedTime = Unsigned16BitLittleIEndian,
                    LastModifiedDate = Unsigned16BitLittleIEndian,
                    CRC32 = Unsigned32BitLittleIEndian,
                    CompressedSize = Unsigned32BitLittleIEndian,
                    UncompressedSize = Unsigned32BitLittleIEndian,
                    FileNameLength = Unsigned16BitLittleIEndian,
                    ExtrasLength = Unsigned16BitLittleIEndian,
                    FileCommentLenght = Unsigned16BitLittleIEndian,
                    DiskNumberStarts = Unsigned16BitLittleIEndian,
                    InternalFileAttributes = Unsigned16BitLittleIEndian,
                    EnternalFileAttributes = Unsigned32BitLittleIEndian,
                    LocalHeaderOffset = Unsigned32BitLittleIEndian
                ]
            ),
        // Definition of the end of central directory record
        EndOfCentralDirectoryRecord =
            BinaryFormat.Record(
                [
                    RestOfFile = BinaryFormat.Binary(ZipFileSize - 22),
                    EOCDsignature = Unsigned32BitLittleIEndian,
                    NumberOfThisDisk = Unsigned16BitLittleIEndian,
                    DiskWhereCentralDirectoryStarts = Unsigned16BitLittleIEndian,
                    NumberOfRecordsOnThisDisk = Unsigned16BitLittleIEndian,
                    TotalNumberOfRecords = Unsigned16BitLittleIEndian,
                    CentralDirectorySize = Unsigned32BitLittleIEndian,
                    OffsetToStart = Unsigned32BitLittleIEndian
                ]
            ),
        //Formatter used for building a table of all files in te central directory
        CentralHeaderFormatter =
            BinaryFormat.Choice(
                Unsigned32BitLittleIEndian,
                // Should contain the signature
                each
                    if _ <> CentralHeaderSignature // Test if the signature is not there
                    then
                        BinaryFormat.Record(
                            [
                                LocalHeaderOffset = null,
                                CompressedSize = null,
                                FileNameLength = null,
                                HeaderSize = null,
                                IsValid = false,
                                Filename = null
                            ]
                        )
                    // if so create a dummy entry 
                    else
                        BinaryFormat.Choice(
                            //Catch the staticly sized part of the central header
                            BinaryFormat.Binary(CentralHeaderSize),
                            //Create a record containing the files size, offset(of the local header), name, etc.. 
                            each
                                BinaryFormat.Record(
                                    [
                                        LocalHeaderOffset = CentralDirectoryHeader(_)[LocalHeaderOffset],
                                        CompressedSize = CentralDirectoryHeader(_)[CompressedSize],
                                        FileNameLength = CentralDirectoryHeader(_)[FileNameLength],
                                        HeaderSize =
                                            LocalHeaderSize
                                            + CentralDirectoryHeader(_)[FileNameLength]
                                            + CentralDirectoryHeader(_)[ExtrasLength],
                                        IsValid = true,
                                        Filename = BinaryFormat.Text(CentralDirectoryHeader(_)[FileNameLength])
                                    ]
                                ),
                            type binary
                        )
            ),
        //Get a record of the end of central directory, this contains the offset of the central header so we can itterate from that position
        EOCDR = EndOfCentralDirectoryRecord(ZipFileBuffer),
        //Get the central directory as a binary extract
        CentralDirectory =
            Binary.Range(
                ZipFileBuffer,
                EOCDR[OffsetToStart]
            ),
        //A list formatter for the central directory  
        CentralDirectoryFormatter =
            BinaryFormat.List(
                CentralHeaderFormatter,
                each _[IsValid] = true
            ),
        //Get a Table from Records containing the file info extracted from the central directory
        FilesTable =
            Table.FromRecords(
                List.RemoveLastN(
                    CentralDirectoryFormatter(CentralDirectory),
                    1
                )
            ),
        //Add the binary to the table and decompress it
        ReturnValue =
            Table.AddColumn(
                FilesTable,
                "Content",
                each
                    Binary.Decompress(
                        Binary.Range(
                            ZipFileBuffer,
                            [LocalHeaderOffset] + [HeaderSize],
                            [CompressedSize]
                        ),
                        Compression.Deflate
                    )
            )
    in
        ReturnValue