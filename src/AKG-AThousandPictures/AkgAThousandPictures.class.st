"
!A Thousand Pictures

This class is the story of improving image display speed with GToolkit.

Creating a pillar file that has multiple images, e.g. jpg files, referenced and displayed will likely fail to scroll smoothly due to the delay while the images are being loaded and scaled in the UI process.

A quick look at the code suggests several potential improvements:

- ${method:name=ImageReadWriter class>>#gtFormFromFileReference:}$ wraps the stream in a ${class:name=ZnPositionableReadStream}$ twice.  This adds two layers of unnecessary buffering and anyway ${class:name=ZnBufferedReadStream}$ can position: if the underlying stream does.
- ${method:name=ZnBufferedReadStream>>#upToEnd}$  makes multiple calls to the primitive to read buffers from the file and uses a ${class:name=WriteStream}$ which grows its buffer in steps, so files larger than the default buffer size will generate unnecessary copying and garbage collection.
-- Ask the stream for it's size, or 0 on error.  Get the size, then anything remaining.
- Keep thumbnails of the images to reduce the file I/O and processing times.
- If the image is larger than the required display area, scale the form down to reduce memory consumption.
- Load images in a background process.  A template should be shown until the image is loaded (may be blank).
- Extend PluginBasedJPEGReadWriter to accept a file name and return the form data (avoiding the need to read the file contents in to object memory).
- Write the image directly to the underlying canvas, e.g. Moz2D
- Use asynchronouse file I/O.

Looking at the first two points above...

!!Baseline File Reading Performance 

Since ${class:name=PluginBasedJPEGReadWriter}$ loads the entire file in to a ByteArray, first measure the performance of reading the file in to memory.

- All measurements below are made with three JPG files held on an in-memory (tempfs) file system.
- The file sizes are: 330kB, 1.6MB and 4.1MB.

On my Dell XPS13 9333 (2012 model):

[[[language=smalltalk
AkgAThousandPictures new bench01: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ]).
""'330.35 kB: 1016 at 33.82607537621521/s
1.56 MB: 198 at 6.59780073308897/s
4.14 MB: 58 at 1.927550681289465/s
'""
]]]


!!Buffering the buffered buffer

GToolkit loads images using ${method:name=ImageReadWriter class>>#gtFormFromFileReference:}$

The method definition as at 2 Apr 2019 is shown below:

[[[language=bash
ImageReadWriter class>>gtFormFromFileReference: aFileReference
	<return: #Form>
	^ aFileReference binaryReadStreamDo: [ :aStream | 
			| aPositionableReadStream |
			aPositionableReadStream := ZnPositionableReadStream on: aStream.
			ImageReadWriter formFromStream: aPositionableReadStream ]	
]]]

and

[[[language=bash
ImageReadWriter class>>formFromStream: aBinaryReadStream
	""Answer a Form of the image stored on aBinaryReadStream.
	This will (normally) autodetect the format and delegate to the correct concrete subclass.
	Closes aBinaryReadStream when done.""
	
	""ImageReadWriter formFromStream: 'test.png' asFileReference binaryReadStream""
	""ImageReadWriter formFromStream: 'test.jpg' asFileReference binaryReadStream""

	| positionableReadStream reader readerClass form |
	positionableReadStream := ZnPositionableReadStream on: aBinaryReadStream.
	readerClass := self readerClassFromStream: positionableReadStream.
	reader := readerClass new on: positionableReadStream.
	form := reader nextImage.
	aBinaryReadStream close.
	^ form	
]]]

We can see that getting the data as a ByteArray in the two methods above can be collapsed down to: 

[[[language=smalltalk
| byteArray aFileReference |

aFileReference binaryReadStreamDo: [ :stream | | bStream |
	bStream := ZnPositionableReadStream on: 
		(ZnPositionableReadStream on: 
			stream).
	byteArray := bStream upToEnd].
]]]


First optimisation, remove the unnecessary ${class:name=ZnPositionableReadStream}$ :

[[[language=smalltalk
AkgAThousandPictures new bench02: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ])

""'330.35 kB: 26563 at 885.403819872671/s
1.56 MB: 461 at 15.340077199520831/s
4.14 MB: 126 at 4.183128050197537/s
'""
]]]


!!Growing the write buffer

${method:name=ZnBufferedReadStream>>#upToEnd}$ eventually calls ${method:name=WriteStream>>#nextPutAll:}$ which grows the buffer in steps as it retrieves the contents of the file.

Check the number of times the write buffer is grown while reading i4.0M.jpg (note that this requires adding some logging to  ${method:name=WriteStream>>#nextPutAll:}$, see the comment in ${method:name=AkgAThousandPictures>>#bench03:}$ AkgAThousandPictures>>bench03::

[[[language=smalltalk
AkgAThousandPictures new bench03: '/dev/shm/pics/i4.0M.jpg' asFileReference
""'Number of log entries: 15'""
]]]


If we request the number of bytes in the file a single buffer is allocated, populated and returned, reducing the amount of data copying and garbage collection:

[[[language=smalltalk
AkgAThousandPictures new bench04: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ])

""'330.35 kB: 158614 at 5286.604672866047/s
1.56 MB: 2047 at 68.19468967585036/s
4.14 MB: 562 at 18.71773522064946/s
'""
]]]


Things are looking good so far (reading files from disk to a ByteArray):

|! Size |! Initial Speed |! Final Speed |! Ratio
|{ 330K |{ 34            |{ 5286        |{ 155
|{ 1.6M |{ 6.6           |{ 68          |{ 10
|{ 4.1M |{ 1.9           |{ 18          |{ 9

Unfortunately this is only retrieving the data from the disk, it needs to be converted to a ${class:name=Form}$ for display.


!!Baseline JPG Performance

Running the benchmark in a clean GToolkit image from 2 Apr 2019 gives:

[[[language=smalltalk
AkgAThousandPictures new bench05: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ])
""'330.35 kB: 264 at 8.798533577737043/s
1.56 MB: 55 at 1.8209508674347767/s
4.14 MB: 38 at 1.2472511241671316/s
'""
]]]


!!Final Performance

Modifying the system with the changes suggested from the tests above, see:

- ImageReadWriter class>>gtFormFromFileReference:
- ImageReadWriter class>>formFromStream:
- ZnBufferedReadStream>>upToEnd
- ZnBufferedReadStream>>savingPositionDo:


[[[language=smalltalk
AkgAThousandPictures new bench05: (#('i323K.jpg' 'i1.5M.jpg' 'i4.0M.jpg')
	collect: [ :each | '/dev/shm/pics' asFileReference / each ])
""'330.35 kB: 345 at 11.477809568168208/s
1.56 MB: 68 at 2.253297103850487/s
4.14 MB: 65 at 2.159540184059271/s
'""
]]]


|! Size |! Initial Speed |! Final Speed |! Ratio
|{ 330K |{ 8.8           |{ 11.5        |{ 1.3
|{ 1.6M |{ 1.8           |{ 2.3         |{ 1.2
|{ 4.1M |{ 1.2           |{ 2.2         |{ 1.8

"
Class {
	#name : #AkgAThousandPictures,
	#superclass : #Object,
	#category : #'AKG-AThousandPictures'
}

{ #category : #convenience }
AkgAThousandPictures class >> openDocument [
	"Open an inspector on my story (class comments)"
	<script>

	GtInspector openOnPlayBook: (GtDocument forClass: self)
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench01: fileCollection [
	"Benchmark the set of supplied files using the original stream structure as it exists in Pharo 7 April 2019"

	| reportStream |

	reportStream := String new writeStream.
	fileCollection do: [ :file | | bench |
		3 timesRepeat: [ Smalltalk garbageCollect ].
		bench := [ file asFileReference binaryReadStreamDo: [ :stream | | bStream |
			bStream := ZnPositionableReadStream on: 
				(ZnPositionableReadStream on: 
					stream).
		bStream upToEnd] ] benchFor: 30 seconds.
		file asFileReference size humanReadableSIByteSizeOn: reportStream.
		reportStream
			<< ': ';
			print: bench iterations;
			<< ' at ';
			print: bench frequency asFloat;
			<< '/s';
			cr ].
	^reportStream contents
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench02: fileCollection [
	"Benchmark the set of supplied files using streams not wrapped in ZnPositionableReadStream"

	| reportStream |

	reportStream := String new writeStream.
	fileCollection do: [ :file | | bench |
		3 timesRepeat: [ Smalltalk garbageCollect ].
		bench := [ file asFileReference binaryReadStreamDo: [ :stream |
			stream upToEnd] ] benchFor: 30 seconds.
		file asFileReference size humanReadableSIByteSizeOn: reportStream.
		reportStream
			<< ': ';
			print: bench iterations;
			<< ' at ';
			print: bench frequency asFloat;
			<< '/s';
			cr ].
	^reportStream contents
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench03: aFileReference [
	"Count the number of buffer expansions performed by ZnBufferedReadStream when reading the entire contents of the supplied file.
	Note that WriteStream>>nextPutAll: must have the following logging added to it first.  Replace:
	
	self growTo: newEnd + 10
		
	with
	
	{collection size. newEnd+10. (collection size - (newEnd+10)) abs.} asBeaconSignal emit.
		self growTo: newEnd + 10"

	| logger contents |

	logger := MemoryLogger new.
	logger runDuring: [ aFileReference asFileReference binaryReadStreamDo:
		[ :stream | contents := stream upToEnd ] ].
	self assert: contents size = aFileReference asFileReference size.
	^String streamContents: [ :stream |
		stream 
			<< 'Number of log entries: ';
			print: logger recordings size;
			cr ]
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench04: fileCollection [
	"Benchmark the set of supplied files using:
	- streams not wrapped in ZnPositionableReadStream
	- Proposed #upToEnd modification (Use #next: file size)"

	| reportStream |

	reportStream := String new writeStream.
	fileCollection do: [ :file | | bench |
		3 timesRepeat: [ Smalltalk garbageCollect ].
		bench := [ file asFileReference binaryReadStreamDo: [ :stream | | contents |
			contents := stream next: file asFileReference size.
			"#upToEnd would check to see if at end and get anything that is missing.
			Short-cut for now by checking that the entire contents were in fact retrieved."
			self assert: stream atEnd.
			self assert: contents size = file asFileReference size.
			] ] benchFor: 30 seconds.
		file asFileReference size humanReadableSIByteSizeOn: reportStream.
		reportStream
			<< ': ';
			print: bench iterations;
			<< ' at ';
			print: bench frequency asFloat;
			<< '/s';
			cr ].
	^reportStream contents
]

{ #category : #benchmarking }
AkgAThousandPictures >> bench05: fileCollection [
	"Benchmark the set of supplied files using ImageReadWriter class>>gtFormFromFileReference: as it exists in Pharo 7 April 2019"

	| reportStream |

	reportStream := String new writeStream.
	fileCollection do: [ :file | | bench |
		3 timesRepeat: [ Smalltalk garbageCollect ].
		bench := [ ImageReadWriter gtFormFromFileReference: file ] benchFor: 30 seconds.
		file asFileReference size humanReadableSIByteSizeOn: reportStream.
		reportStream
			<< ': ';
			print: bench iterations;
			<< ' at ';
			print: bench frequency asFloat;
			<< '/s';
			cr ].
	^reportStream contents
]
