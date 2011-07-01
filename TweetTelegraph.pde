/*
Ardunio code that will manage a telegraph key and sounder (or suitable proxies).  Unlike oldie-timie 
telegraph systems this code assumes a half duplex setup.  You can either send or recieve at the same 
time, not both. This is fascilitated by a switch of some kind (hopefully of the badass knife variety.)

Communication with the sounder is done via serial interface.  The protocol is a simple one in which null 
terminated strings are sent to the device.  Similarly, messages from the key are transmitted via the same 
connection in null terminated string format.

@author Kimberly Horne
*/

/*
The base time unit for all operations.  Morse code input and output is measured as multiples of this 
value.  The smaller the number the faster the output (or faster your fingers will need to be on the key).
*/
int baseUnit = 1000;

/*
Time between letters.
 */
int letterSpace = baseUnit * 3;

/*
Time between words.
*/
int wordSpace = baseUnit * 7;

/*
Time between messages.
*/
int messageEnd = baseUnit * 15;

/*
Pin that is connected to the telegraph key (or button) that allows for input of Morse code messages.
*/
int keyPin = 11;

/*
Pin connected to the telegraph sounder (or speaker or LED or whatever you've got rigged up as a sounder) 
that allows for output of messages from serial as well as local echo for messages entered from the key.
*/
int sounderPin = 13;

/*
Pin that switches between input mode on the key (HIGH) and output mode to the sounder (LOW)
*/
int switchPin = 12;

/**
Current phrase being read over the serial connection.
*/
char phrase[200];

/**
Length of current phrase (in characters).
*/
int phraseLength = 0;

/**
Supported character array.
*/
char characters [] = {
'a',
'b',
'c',
'd',
'e',
'f',
'g',
'h',
'i',
'j',
'k',
'l',
'm',
'n',
'o',
'p',
'q',
'r',
's',
't',
'u',
'v',
'w',
'x',
'y',
'z',
'@',
'#'};

/**
Total number of characters we support.
*/
int charactersLength = 29;

// 
/**
Array of sounds representing the above-defined characters.
Two bits per item, 1 == short, 2 == long, shift left after each read.  
Stop when 0;
*/
int sounds [] = {
  buildSound("sl"),      //a
  buildSound("lsss"),    //b
  buildSound("lsls"),   //c
  buildSound("lss"),    //d
  buildSound("s"),      //e
  buildSound("ssls"),    //f
  buildSound("lls"),    //g
  buildSound("ssss"),   //h
  buildSound("ss"),     //i
  buildSound("slll"),  //j
  buildSound("lsl"),    //k 
  buildSound("slss"),    //l
  buildSound("ll"),      //m
  buildSound("ls") ,     //n
  buildSound("lll"),    //o
  buildSound("slls"),    //p
  buildSound("llsl"),    //q
  buildSound("sls"),    //r
  buildSound("sss"),    //s
  buildSound("l"),      //t
  buildSound("ssl"),    //u
  buildSound("sssl"),   //v
  buildSound("sll"),    //w
  buildSound("lssl"),    //x
  buildSound("lsll"),    //y
  buildSound("llss"),    //z
  buildSound("sllsls"),   //@
  buildSound("slsss")};   //# (but really & - there is no official Morse code for #)
  
/**
Build an integer representing the dot/dash series defining the provided character.  Each segment 
is contained within a 2 bit block of the integer.  If the sound is short, the first bit is set. 
If it's long, the second.

Should probably be done in another program and the results just inlined as constants in the 
sounds array above.
*/
int buildSound(char *letter) {
  int i = 0;
  int offset = 0;
  int result = 0;
  char c;
  while ((c = letter[i]) != '\0') { // until there are no s's or l's left to parse
    if (c == 's') 
      result += (1 << i*2);
    else if (c == 'l')
      result += (2 << i*2);
    i++;
  }
  return result;
}

void setup() {
  pinMode(sounderPin, OUTPUT);
  pinMode(keyPin, INPUT);
  digitalWrite(keyPin, HIGH);
  Serial.begin(9600);
  establishContact();
}

/**
Wait for a connection from the server.  Tick/Tock until it occurs.
*/
void establishContact() {
  while (Serial.available() <= 0) {
    digitalWrite(sounderPin, HIGH);
    delay(1000);
    digitalWrite(sounderPin, LOW);
    delay(1000);
  }
  Serial.read(); // discard first byte.  This protocol could use some cleaning up.
}

void loop() {
  if (digitalRead(switchPin) == HIGH) {
    // read the input from the key
    doRead();
  }
  else {  
    // post messages to the sounder
    int inByte;
    if (Serial.available() > 0) { // go while there is data to read.
      inByte = Serial.read();
      phrase[phraseLength++] = (char)inByte;
      if (inByte == '\0') {
        // end of string - play her
        play(phrase);
        phraseLength = 0; // reset
      }
    }
  }
}

/**
 * Read input from the key and convert it to characters.
 */
void doRead() {
  char message[140];
  int position=0; // the position of the message we're reading
  int character = 0; // the current character being read
  int characterPosition = 0; //the position within the current character being read
  
  int highTime = 0; // the amount of time the key has been high
  int lowTime = 0; // the amount of time the key has been low
  int lastRead = LOW; // last read state
  int timer = 0; // the marker for last event
  int hasStarted = 0; // have we gotten our initial high mark
  int startTime = -1; // the time we started.  Marked by the first HIGH occurance we get
  int read; // current read state
  
  while (lowTime < messageEnd) { //loop until we've hit the low marker signifying end of message
    read = digitalRead(keyPin) == HIGH ? LOW : HIGH; // logically high but input is actually low.  Conceptually easier for my small brain to follow
    digitalWrite(sounderPin, read); // echo the current read state to the sounder
    if (read == HIGH) { // key is pressed
      if (!hasStarted) {
        hasStarted = 1; // first read of the first character
        startTime = millis();
      }
      if (lastRead == LOW) { // it wasnt pressed before        
        timer = millis();
        lastRead = HIGH;
        
        if (lowTime >= letterSpace && lowTime < wordSpace) { //we've moved between letters - figure out the last letter and add it to the message
          updateMessage(message, &position, character);
          character = 0; // reset the character
          characterPosition = 0;
        }
        else if (lowTime >= wordSpace && lowTime < messageEnd) { // new word - add a space
          message[position++] = ' ';
          if (position == 140) { // we've maxed out the message - send it
            sendMessage(message, position);
            position = 0;
          }
          character = 0; // reset the character
          characterPosition = 0;
        }
      }
      lowTime = 0; // reset the low time and high time counter
      highTime = millis() - timer;
    }
    else { // key is not pressed
      if (lastRead == HIGH) { // but it was before
        timer = millis();
        lastRead = LOW;
        if (highTime < baseUnit * 3) { // less than 3 * base unit means short
          character += (1 << characterPosition++ * 2);
        }
        else if (highTime >= baseUnit *3) { // more than 3 * base unit means long
          character += (2 << characterPosition++ * 2);
        }        
      }
      if (hasStarted) {
        lowTime = millis() - timer;
        highTime = 0;
      }
      
    }   
    delay(10); // this can probably be tweaked upwards some, but not too much for fast fingers
  }

  if (characterPosition > 0) { // clean up the remainder of the message
    updateMessage(message, &position, character);
  }

  sendMessage(message, position);
  digitalWrite(sounderPin, LOW);
}

/**
Update the message with the provided new character.  If we've exhausted the length of a Tweet then send what we have and start building another.
*/
void updateMessage(char * message, int *position, int character) {
  for (int i = 0; i < charactersLength; i++) {
    if (sounds[i] == character) { // found the right character
      message[(*position)++] = characters[i];
      if (*position == 140) { // we've maxed out the message - send it
        sendMessage(message, *position);
        *position = 0;         
      }  
    }
  }
}

/**
Send the message across the serial port.  Null terminated.
*/
void sendMessage(char * message, int length) {
  for (int i=0; i < length; i++) {
    Serial.print(message[i]);
  }
  if (length > 0)
    Serial.print('\0');
}

/**
Play the provided string on the sounder.
*/
void play(char *string) {
  for (int i = 0; i < phraseLength; i++) {
    char c = string[i];
    if (c == ' ')
      delay(wordSpace);
    else
      playChar(c);
  }
}

/**
Play the provided character on the sounder.
*/
void playChar(char c) {
  unsigned long end;
  for (int i = 0; i < charactersLength; i++) { //loop over all supported characters
    if (characters[i] == c) { //if we find the character in the message, play it
      int sound = sounds[i];
      while (sound !=0) {
        int segment = sound & 3; // slice out a 2 bit segment of the character
        if (segment == 1) { // short pulse
          end = millis() + baseUnit;
          digitalWrite(sounderPin, HIGH);
          delay(baseUnit);
          digitalWrite(sounderPin, LOW);          
        }
        else if (segment == 2) { // long pulse
          end = millis() + baseUnit * 3;
          digitalWrite(sounderPin, HIGH);
          delay(baseUnit * 3);
          digitalWrite(sounderPin, LOW);   
        }
        else {
//          Serial.print("WTF?"); // shouldn't happen based on how we construct the sounds but if it does.. woah.
        }
        sound >>= 2; // shift two bits off and go to the next sound (possibly).
        delay(baseUnit);
      }
      delay(letterSpace);
      return;
    }
  }
}
