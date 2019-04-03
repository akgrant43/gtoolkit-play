Extension { #name : #ImageReadWriter }

{ #category : #'*AKG-AThousandPictures' }
ImageReadWriter class >> gtFormFromFileReference: aFileReference [
	<return: #Form>

	| stream reader readerClass form |

	stream := GtBufferedReadStream on: 
		(aFileReference fileSystem binaryReadStreamOn: aFileReference path).
	form := [
		readerClass := self readerClassFromStream: stream.
		reader := readerClass new on: stream.
		reader nextImage ]
			ensure: [ stream close ].
	^ form

]
