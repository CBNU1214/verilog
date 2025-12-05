import sys
import re

def convert_hex_with_gaps(input_file, output_file, fill_byte='00'):

    memory_image = []
    current_address = 0

    with open(input_file, 'r') as f_in:
        for line in f_in:
            line = line.strip()
            if not line:
                continue

            if line.startswith('@'):
                match = re.search(r'@([0-9a-fA-F]+)', line)
                if match:
                    target_address = int(match.group(1), 16)
                    

                    if target_address > current_address:
                        gap_size = target_address - current_address
                        memory_image.extend([fill_byte] * gap_size)
                    
                    current_address = target_address

            else:
                bytes_on_line = line.split()
                memory_image.extend(bytes_on_line)
                current_address += len(bytes_on_line)

    with open(output_file, 'w') as f_out:
        f_out.write("@0\n")
        
        for i in range(0, len(memory_image), 4):

            word = memory_image[i:i+4]
            
            if len(word) < 4:
                word.extend([fill_byte] * (4 - len(word)))
            
            word.reverse()
            f_out.write("".join(word).lower() + "\n")


if __name__ == "__main__":

    if len(sys.argv) != 3:
        print("python3 <script_name>.py <input_file> <output_file>")
        sys.exit(1) 
    input_filename = sys.argv[1]
    output_filename = sys.argv[2]

    convert_hex_with_gaps(input_filename, output_filename)